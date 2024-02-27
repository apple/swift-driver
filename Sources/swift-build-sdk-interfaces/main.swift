//===--------------- main.swift - swift-build-sdk-interfaces ------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import SwiftDriverExecution
import SwiftDriver
#if os(Windows)
import CRT
#elseif os(iOS) || os(macOS) || os(tvOS) || os(watchOS)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

import TSCBasic // <<<
import class TSCBasic.DiagnosticsEngine
import class TSCBasic.ProcessSet
import enum TSCBasic.ProcessEnv
import func TSCBasic.withTemporaryFile
import struct TSCBasic.AbsolutePath
import var TSCBasic.localFileSystem
import var TSCBasic.stderrStream

let diagnosticsEngine = DiagnosticsEngine(handlers: [Driver.stderrDiagnosticsHandler])

func getArgument(_ flag: String, _ env: String? = nil) -> String? {
  if let id = CommandLine.arguments.firstIndex(of: flag) {
    let nextId = id.advanced(by: 1)
    if nextId < CommandLine.arguments.count {
      return CommandLine.arguments[nextId]
    }
  }
  if let env = env {
    return ProcessEnv.vars[env]
  }
  return nil
}

func getArgumentAsPath(_ flag: String, _ env: String? = nil) throws -> AbsolutePath? {
  if let raw = getArgument(flag, env) {
    return try VirtualPath(path: raw).absolutePath
  }
  return nil
}

guard let rawOutputDir = getArgument("-o") else {
  diagnosticsEngine.emit(.error("need to specify -o"))
  exit(1)
}

/// When -core is specified, only most significant modules are handled. Currently,
/// they are Foundation and anything below.
let coreMode = CommandLine.arguments.contains("-core")

/// Verbose to print more info
let verbose = CommandLine.arguments.contains("-v")

/// Skip executing the jobs
let skipExecution = CommandLine.arguments.contains("-n")

do {
  let sdkPathArg = try getArgumentAsPath("-sdk", "SDKROOT")
  guard let sdkPath = sdkPathArg else {
    diagnosticsEngine.emit(.error("need to set SDKROOT"))
    exit(1)
  }
  if !localFileSystem.exists(sdkPath) {
    diagnosticsEngine.emit(error: "cannot find sdk: \(sdkPath.pathString)")
    exit(1)
  }
  let logDir = try getArgumentAsPath("-log-path")
  let jsonPath = try getArgumentAsPath("-json-path")
  let collector = SDKPrebuiltModuleInputsCollector(sdkPath, diagnosticsEngine)
  var outputDir = try VirtualPath(path: rawOutputDir).absolutePath!
  // if the given output dir ends with 'prebuilt-modules', we should
  // append the SDK version number so all modules will built into
  // the SDK-versioned sub-directory.
  if outputDir.basename == "prebuilt-modules" {
    outputDir = try AbsolutePath(validating: collector.versionString, relativeTo: outputDir)
  }
  if !localFileSystem.exists(outputDir) {
    try localFileSystem.createDirectory(outputDir, recursive: true)
  }
  let swiftcPathRaw = ProcessEnv.vars["SWIFT_EXEC"]
  var swiftcPath: AbsolutePath
  if let swiftcPathRaw = swiftcPathRaw {
    let virtualPath = try VirtualPath(path: swiftcPathRaw)
    guard let absolutePath = virtualPath.absolutePath else {
      diagnosticsEngine.emit(error: "value of SWIFT_EXEC is not a valid absolute path: \(swiftcPathRaw)")
      exit(1)
    }
    swiftcPath = absolutePath
  } else {
    swiftcPath = try AbsolutePath(validating: "Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc",
                                  relativeTo: sdkPath.parentDirectory
                                                 .parentDirectory
                                                 .parentDirectory
                                                 .parentDirectory
                                                 .parentDirectory)
  }
  if !localFileSystem.exists(swiftcPath) {
    diagnosticsEngine.emit(error: "cannot find swift compiler: \(swiftcPath.pathString)")
    exit(1)
  }

  let sysVersionFile = outputDir.appending(component: "SystemVersion.plist")
  if localFileSystem.exists(sysVersionFile) {
    try localFileSystem.removeFileTree(sysVersionFile)
  }
  // Copy $SDK/System/Library/CoreServices/SystemVersion.plist file from the SDK
  // into the prebuilt module file to keep track of which SDK build we are generating
  // the modules from.
  try localFileSystem.copy(from: sdkPath.appending(component: "System")
                              .appending(component: "Library")
                              .appending(component: "CoreServices")
                              .appending(component: "SystemVersion.plist"),
                           to: sysVersionFile)
  let processSet = ProcessSet()
  let inputTuple = try collector.collectSwiftInterfaceMap()
  let allAdopters = inputTuple.adopters
  let currentABIDir = try getArgumentAsPath("-current-abi-dir")
  try SwiftAdopter.emitSummary(allAdopters, to: currentABIDir)
  let inputMap = inputTuple.inputMap
  let allModules = coreMode ? ["Foundation"] : Array(inputMap.keys)
  try withTemporaryFile(suffix: ".swift") {
    let tempPath = $0.path
    try localFileSystem.writeFileContents(tempPath, body: {
      for module in allModules {
        $0 <<< "import " <<< module <<< "\n"
      }
    })
    let executor = try SwiftDriverExecutor(diagnosticsEngine: diagnosticsEngine,
                                           processSet: processSet,
                                           fileSystem: localFileSystem,
                                           env: ProcessEnv.vars)
    var args = ["swiftc",
                "-target", collector.targetTriple,
                tempPath.description,
                "-sdk", sdkPath.pathString]
    let mcpFlag = "-module-cache-path"
    // Append module cache path if given by the client
    if let mcp = getArgument(mcpFlag) {
      args.append(mcpFlag)
      args.append(mcp)
      // Create module cache dir if absent.
      let mcpPath = try VirtualPath(path: mcp).absolutePath!
      if !localFileSystem.exists(mcpPath) {
        try localFileSystem.createDirectory(mcpPath, recursive: true)
      }
    }
    let baselineABIDir = try getArgumentAsPath("-baseline-abi-dir")
    var driver = try Driver(args: args,
                            diagnosticsOutput: .engine(diagnosticsEngine),
                            executor: executor,
                            compilerExecutableDir: swiftcPath.parentDirectory)
    let (jobs, danglingJobs) = try driver.generatePrebuiltModuleGenerationJobs(with: inputMap,
      into: outputDir, exhaustive: !coreMode, dotGraphPath: getArgumentAsPath("-dot-graph-path"),
      currentABIDir: currentABIDir, baselineABIDir: baselineABIDir)
    if verbose {
      Driver.stdErrQueue.sync {
        stderrStream <<< "job count: \(jobs.count + danglingJobs.count)\n"
        stderrStream.flush()
      }
    }
    if skipExecution {
      exit(0)
    }
    let delegate = PrebuiltModuleGenerationDelegate(jobs, diagnosticsEngine, verbose, logDir)
    defer {
      if let jsonPath = jsonPath {
        try! delegate.emitJsonOutput(to: jsonPath)
      }
    }
    do {
      try executor.execute(workload: DriverExecutorWorkload.init(jobs, nil, continueBuildingAfterErrors: true),
                           delegate: delegate, numParallelJobs: 128)
    } catch {
      // Only fail when critical failures happened.
      if delegate.hasCriticalFailure {
        exit(1)
      }
    }
    do {
      if !danglingJobs.isEmpty && delegate.shouldRunDanglingJobs {
        try executor.execute(workload: DriverExecutorWorkload.init(danglingJobs, nil, continueBuildingAfterErrors: true), delegate: delegate, numParallelJobs: 128)
      }
    } catch {
      // Failing of dangling jobs don't fail the process.
      exit(0)
    }
  }
} catch {
  print("error: \(error)")
  exit(1)
}
