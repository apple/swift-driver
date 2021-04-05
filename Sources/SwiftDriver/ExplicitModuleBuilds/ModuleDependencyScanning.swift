//===--------------- ModuleDependencyScanning.swift -----------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Foundation
import TSCBasic
import SwiftOptions

extension Diagnostic.Message {
  static func warn_scanner_frontend_fallback() -> Diagnostic.Message {
    .warning("Fallback to `swift-frontend` dependency scanner invocation")
  }
}

internal extension Driver {
  /// Precompute the dependencies for a given Swift compilation, producing a
  /// dependency graph including all Swift and C module files and
  /// source files.
  mutating func dependencyScanningJob() throws -> Job {
    let (inputs, commandLine) = try dependencyScannerInvocationCommand()

    // Construct the scanning job.
    return Job(moduleName: moduleOutputInfo.name,
               kind: .scanDependencies,
               tool: try toolchain.getToolPathHandle(.swiftCompiler),
               commandLine: commandLine,
               displayInputs: inputs,
               inputs: inputs,
               primaryInputs: [],
               outputs: [TypedVirtualPath(file: .standardOutput, type: .jsonDependencies)],
               supportsResponseFiles: true)
  }

  /// Generate a full command-line invocation to be used for the dependency scanning action
  /// on the target module.
  mutating func dependencyScannerInvocationCommand()
  throws -> ([TypedVirtualPath],[Job.ArgTemplate]) {
    // Aggregate the fast dependency scanner arguments
    var inputs: [TypedVirtualPath] = []
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }
    commandLine.appendFlag("-frontend")
    commandLine.appendFlag("-scan-dependencies")
    try addCommonFrontendOptions(commandLine: &commandLine, inputs: &inputs,
                                 bridgingHeaderHandling: .precompiled,
                                 moduleDependencyGraphUse: .dependencyScan)
    // FIXME: MSVC runtime flags

    // Pass in external target dependencies to be treated as placeholder dependencies by the scanner
    if let externalBuildArtifacts = externalBuildArtifacts {
      let dependencyPlaceholderMapFile =
        try serializeExternalDependencyArtifacts(externalBuildArtifacts: externalBuildArtifacts)
      commandLine.appendFlag("-placeholder-dependency-module-map-file")
      commandLine.appendPath(dependencyPlaceholderMapFile)
    }

    // Pass on the input files
    commandLine.append(contentsOf: inputFiles.map { .path($0.file) })
    return (inputs, commandLine)
  }

  /// Serialize a map of placeholder (external) dependencies for the dependency scanner.
  func serializeExternalDependencyArtifacts(externalBuildArtifacts: ExternalBuildArtifacts)
  throws -> VirtualPath {
    let (externalTargetModulePathMap, externalModuleInfoMap)  = externalBuildArtifacts
    var placeholderArtifacts: [SwiftModuleArtifactInfo] = []

    // Explicit external targets
    for (moduleId, binaryModulePath) in externalTargetModulePathMap {
      let modPath = TextualVirtualPath(path: VirtualPath.absolute(binaryModulePath).intern())
      placeholderArtifacts.append(
          SwiftModuleArtifactInfo(name: moduleId.moduleName,
                                  modulePath: modPath))
    }

    // All other already-scanned Swift modules
    for (moduleId, moduleInfo) in externalModuleInfoMap
    where !externalTargetModulePathMap.keys.contains(moduleId) {
      guard case .swift(_) = moduleId else { continue }
      placeholderArtifacts.append(
          SwiftModuleArtifactInfo(name: moduleId.moduleName,
                                  modulePath: moduleInfo.modulePath))
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted]
    let contents = try encoder.encode(placeholderArtifacts)
    return .temporaryWithKnownContents(.init("\(moduleOutputInfo.name)-placeholder-modules.json"),
                                       contents)
  }

  mutating func performDependencyScan() throws -> InterModuleDependencyGraph {
    let scannerJob = try dependencyScanningJob()
    let forceResponseFiles = parsedOptions.hasArgument(.driverForceResponseFiles)
    let dependencyGraph: InterModuleDependencyGraph

    // If `-nonlib-dependency-scanner` was specified or the libSwiftScan library cannot be found,
    // attempt to fallback to using `swift-frontend -scan-dependencies` invocations for dependency
    // scanning.
    var fallbackToFrontend = parsedOptions.hasArgument(.driverScanDependenciesNonLib)
    let scanLibPath = try Self.getScanLibPath(of: toolchain, hostTriple: hostTriple, env: env)
    if try interModuleDependencyOracle
        .verifyOrCreateScannerInstance(fileSystem: fileSystem,
                                       swiftScanLibPath: scanLibPath) == false {
      fallbackToFrontend = true
      diagnosticEngine.emit(.warn_scanner_frontend_fallback())
    }

    if (!fallbackToFrontend) {
      let cwd = workingDirectory ?? fileSystem.currentWorkingDirectory!
      var command = try itemizedJobCommand(of: scannerJob,
                                           forceResponseFiles: forceResponseFiles,
                                           using: executor.resolver)
      // Remove the tool executable to only leave the arguments
      command.removeFirst()
      // We generate full swiftc -frontend -scan-dependencies invocations in order to also be
      // able to launch them as standalone jobs. Frontend's argument parser won't recognize
      // -frontend when passed directly.
      if command.first == "-frontend" {
        command.removeFirst()
      }
      dependencyGraph =
        try interModuleDependencyOracle.getDependencies(workingDirectory: cwd,
                                                        commandLine: command)
    } else {
      // Fallback to legacy invocation of the dependency scanner with
      // `swift-frontend -scan-dependencies`
      dependencyGraph =
        try self.executor.execute(job: scannerJob,
                                  capturingJSONOutputAs: InterModuleDependencyGraph.self,
                                  forceResponseFiles: forceResponseFiles,
                                  recordedInputModificationDates: recordedInputModificationDates)
    }
    return dependencyGraph
  }

  mutating func performBatchDependencyScan(moduleInfos: [BatchScanModuleInfo])
  throws -> [ModuleDependencyId: [InterModuleDependencyGraph]] {
    let batchScanningJob = try batchDependencyScanningJob(for: moduleInfos)
    let forceResponseFiles = parsedOptions.hasArgument(.driverForceResponseFiles)

    // If `-nonlib-dependency-scanner` was specified or the libSwiftScan library cannot be found,
    // attempt to fallback to using `swift-frontend -scan-dependencies` invocations for dependency
    // scanning.
    var fallbackToFrontend = parsedOptions.hasArgument(.driverScanDependenciesNonLib)
    let scanLibPath = try Self.getScanLibPath(of: toolchain, hostTriple: hostTriple, env: env)
    if try interModuleDependencyOracle
        .verifyOrCreateScannerInstance(fileSystem: fileSystem,
                                       swiftScanLibPath: scanLibPath) == false {
      fallbackToFrontend = true
      diagnosticEngine.emit(.warn_scanner_frontend_fallback())
    }

    let moduleVersionedGraphMap: [ModuleDependencyId: [InterModuleDependencyGraph]]
    if (!fallbackToFrontend) {
      let cwd = workingDirectory ?? fileSystem.currentWorkingDirectory!
      var command = try itemizedJobCommand(of: batchScanningJob,
                                           forceResponseFiles: forceResponseFiles,
                                           using: executor.resolver)
      // Remove the tool executable to only leave the arguments
      command.removeFirst()
      // We generate full swiftc -frontend -scan-dependencies invocations in order to also be
      // able to launch them as standalone jobs. Frontend's argument parser won't recognize
      // -frontend when passed directly.
      if command.first == "-frontend" {
        command.removeFirst()
      }
      moduleVersionedGraphMap =
        try interModuleDependencyOracle.getBatchDependencies(workingDirectory: cwd,
                                                             commandLine: command,
                                                             batchInfos: moduleInfos)
    } else {
      // Fallback to legacy invocation of the dependency scanner with
      // `swift-frontend -scan-dependencies`
      moduleVersionedGraphMap = try executeLegacyBatchScan(moduleInfos: moduleInfos,
                                                           batchScanningJob: batchScanningJob,
                                                           forceResponseFiles: forceResponseFiles)
    }
    return moduleVersionedGraphMap
  }

  // Perform a batch scan by invoking the command-line dependency scanner and decoding the resulting
  // JSON.
  fileprivate func executeLegacyBatchScan(moduleInfos: [BatchScanModuleInfo],
                                          batchScanningJob: Job,
                                          forceResponseFiles: Bool)
  throws -> [ModuleDependencyId: [InterModuleDependencyGraph]] {
    let batchScanResult =
      try self.executor.execute(job: batchScanningJob,
                                forceResponseFiles: forceResponseFiles,
                                recordedInputModificationDates: recordedInputModificationDates)
    let success = batchScanResult.exitStatus == .terminated(code: EXIT_SUCCESS)
    guard success else {
      throw JobExecutionError.jobFailedWithNonzeroExitCode(
        type(of: executor).computeReturnCode(exitStatus: batchScanResult.exitStatus),
        try batchScanResult.utf8stderrOutput())
    }
    // Decode the resulting dependency graphs and build a dictionary from a moduleId to
    // a set of dependency graphs that were built for it
    let moduleVersionedGraphMap =
      try moduleInfos.reduce(into: [ModuleDependencyId: [InterModuleDependencyGraph]]()) {
        let moduleId: ModuleDependencyId
        let dependencyGraphPath: VirtualPath
        switch $1 {
          case .swift(let swiftModuleBatchScanInfo):
            moduleId = .swift(swiftModuleBatchScanInfo.swiftModuleName)
            dependencyGraphPath = try VirtualPath(path: swiftModuleBatchScanInfo.output)
          case .clang(let clangModuleBatchScanInfo):
            moduleId = .clang(clangModuleBatchScanInfo.clangModuleName)
            dependencyGraphPath = try VirtualPath(path: clangModuleBatchScanInfo.output)
        }
        let contents = try fileSystem.readFileContents(dependencyGraphPath)
        let decodedGraph = try JSONDecoder().decode(InterModuleDependencyGraph.self,
                                                    from: Data(contents.contents))
        if $0[moduleId] != nil {
          $0[moduleId]!.append(decodedGraph)
        } else {
          $0[moduleId] = [decodedGraph]
        }
      }
    return moduleVersionedGraphMap
  }

  /// Precompute the dependencies for a given collection of modules using swift frontend's batch scanning mode
  mutating func batchDependencyScanningJob(for moduleInfos: [BatchScanModuleInfo]) throws -> Job {
    var inputs: [TypedVirtualPath] = []

    // Aggregate the fast dependency scanner arguments
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }

    // The dependency scanner automatically operates in batch mode if -batch-scan-input-file
    // is present.
    commandLine.appendFlag("-frontend")
    commandLine.appendFlag("-scan-dependencies")
    try addCommonFrontendOptions(commandLine: &commandLine, inputs: &inputs,
                                 bridgingHeaderHandling: .precompiled,
                                 moduleDependencyGraphUse: .dependencyScan)

    let batchScanInputFilePath = try serializeBatchScanningModuleArtifacts(moduleInfos: moduleInfos)
    commandLine.appendFlag("-batch-scan-input-file")
    commandLine.appendPath(batchScanInputFilePath)

    // This action does not require any input files, but all frontend actions require
    // at least one input so pick any input of the current compilation.
    let inputFile = inputFiles.first { $0.type == .swift }
    commandLine.appendPath(inputFile!.file)
    inputs.append(inputFile!)

    // This job's outputs are defined as a set of dependency graph json files
    let outputs: [TypedVirtualPath] = try moduleInfos.map {
      switch $0 {
        case .swift(let swiftModuleBatchScanInfo):
          return TypedVirtualPath(file: try VirtualPath.intern(path: swiftModuleBatchScanInfo.output),
                                  type: .jsonDependencies)
        case .clang(let clangModuleBatchScanInfo):
          return TypedVirtualPath(file: try VirtualPath.intern(path: clangModuleBatchScanInfo.output),
                                  type: .jsonDependencies)
      }
    }

    // Construct the scanning job.
    return Job(moduleName: moduleOutputInfo.name,
               kind: .scanDependencies,
               tool: try toolchain.getToolPathHandle(.swiftCompiler),
               commandLine: commandLine,
               displayInputs: inputs,
               inputs: inputs,
               primaryInputs: [],
               outputs: outputs,
               supportsResponseFiles: true)
  }

  /// Serialize a collection of modules into an input format expected by the batch module dependency scanner.
  func serializeBatchScanningModuleArtifacts(moduleInfos: [BatchScanModuleInfo])
  throws -> VirtualPath {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted]
    let contents = try encoder.encode(moduleInfos)
    return .temporaryWithKnownContents(.init("\(moduleOutputInfo.name)-batch-module-scan.json"),
                                       contents)
  }

  fileprivate func itemizedJobCommand(of job: Job, forceResponseFiles: Bool,
                                      using resolver: ArgsResolver) throws -> [String] {
    let (args, _) = try resolver.resolveArgumentList(for: job,
                                                     forceResponseFiles: forceResponseFiles,
                                                     quotePaths: true)
    return args
  }
}

@_spi(Testing) public extension Driver {
  static func getScanLibPath(of toolchain: Toolchain, hostTriple: Triple,
                             env: [String: String]) throws -> AbsolutePath {
    let sharedLibExt: String
    if hostTriple.isMacOSX {
      sharedLibExt = ".dylib"
    } else {
      sharedLibExt = ".so"
    }
    return try getRootPath(of: toolchain, env: env).appending(component: "lib")
      .appending(component: "swift")
      .appending(component: hostTriple.osNameUnversioned)
      .appending(component: "lib_InternalSwiftScan" + sharedLibExt)
  }

  fileprivate static func getRootPath(of toolchain: Toolchain, env: [String: String])
  throws -> AbsolutePath {
    if let overrideString = env["SWIFT_DRIVER_SWIFT_SCAN_TOOLCHAIN_PATH"] {
      return try AbsolutePath(validating: overrideString)
    }
    return try toolchain.getToolPath(.swiftCompiler)
      .parentDirectory // bin
      .parentDirectory // toolchain root
  }
}
