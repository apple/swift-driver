//===----- PrebuiltModulesJob.swift - Swit prebuilt module Planning -------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import TSCBasic
import SwiftOptions

func isIosMac(_ path: VirtualPath) -> Bool {
  // Infer macabi interfaces by the file name.
  // FIXME: more robust way to do this.
  return path.basenameWithoutExt.contains("macabi")
}

public class PrebuitModuleGenerationDelegate: JobExecutionDelegate {
  var failingModules = Set<String>()
  var commandMap: [Int: String] = [:]
  let diagnosticsEngine: DiagnosticsEngine
  let verbose: Bool
  var failingCriticalOutputs: Set<VirtualPath>
  public init(_ jobs: [Job], _ diagnosticsEngine: DiagnosticsEngine, _ verbose: Bool) {
    self.diagnosticsEngine = diagnosticsEngine
    self.verbose = verbose
    self.failingCriticalOutputs = Set<VirtualPath>(jobs.compactMap(PrebuitModuleGenerationDelegate.getCriticalOutput))
  }

  /// Dangling jobs are macabi-only modules. We should run those jobs if foundation
  /// is built successfully for macabi.
  public var shouldRunDanglingJobs: Bool {
    return !failingCriticalOutputs.contains(where: isIosMac)
  }
  func printJobInfo(_ job: Job, _ start: Bool) {
    guard verbose else {
      return
    }
    for arg in job.commandLine {
      if case .path(let p) = arg {
        if p.extension == "swiftinterface" {
          Driver.stdErrQueue.sync {
            stderrStream <<< (start ? "started: " : "finished: ")
            stderrStream <<< p.absolutePath!.pathString <<< "\n"
            stderrStream.flush()
          }
          return
        }
      }
    }
  }

  static func getCriticalOutput(_ job: Job) -> VirtualPath? {
    return job.moduleName == "Foundation" ? job.outputs[0].file : nil
  }

  public func jobStarted(job: Job, arguments: [String], pid: Int) {
    commandMap[pid] = arguments.reduce("") { return $0 + " " + $1 }
    printJobInfo(job, true)
  }

  public var hasCriticalFailure: Bool {
    return !failingCriticalOutputs.isEmpty
  }

  public func jobFinished(job: Job, result: ProcessResult, pid: Int) {
    switch result.exitStatus {
    case .terminated(code: let code):
      if code == 0 {
        printJobInfo(job, false)
        failingCriticalOutputs.remove(job.outputs[0].file)
      } else {
        failingModules.insert(job.moduleName)
        let result: String = try! result.utf8stderrOutput()
        Driver.stdErrQueue.sync {
          stderrStream <<< "failed: " <<< commandMap[pid]! <<< "\n"
          stderrStream <<< result <<< "\n"
          stderrStream.flush()
        }
      }
#if !os(Windows)
    case .signalled:
      diagnosticsEngine.emit(.remark("\(job.moduleName) interrupted"))
#endif
    }
  }

  public func jobSkipped(job: Job) {
    diagnosticsEngine.emit(.error("\(job.moduleName) skipped"))
  }
}

public struct PrebuiltModuleInput {
  // The path to the input/output of the a module building task.
  let path: TypedVirtualPath
  // The arch infered from the file name.
  let arch: Triple.Arch
  init(_ path: TypedVirtualPath) {
    let baseName = path.file.basename
    let arch = baseName.prefix(upTo: baseName.firstIndex(where: { $0 == "-" || $0 == "." })!)
    self.init(path, Triple.Arch.parse(arch)!)
  }
  init(_ path: TypedVirtualPath, _ arch: Triple.Arch) {
    self.path = path
    self.arch = arch
  }
}

typealias PrebuiltModuleOutput = PrebuiltModuleInput

public struct SDKPrebuiltModuleInputsCollector {
  let sdkPath: AbsolutePath
  let nonFrameworkDirs = [RelativePath("usr/lib/swift"),
                          RelativePath("System/iOSSupport/usr/lib/swift")]
  let frameworkDirs = [RelativePath("System/Library/Frameworks"),
                      RelativePath("System/iOSSupport/System/Library/Frameworks")]
  let sdkInfo: DarwinToolchain.DarwinSDKInfo
  let diagEngine: DiagnosticsEngine
  public init(_ sdkPath: AbsolutePath, _ diagEngine: DiagnosticsEngine) {
    self.sdkPath = sdkPath
    self.sdkInfo = DarwinToolchain.readSDKInfo(localFileSystem,
                                               VirtualPath.absolute(sdkPath).intern())!
    self.diagEngine = diagEngine
  }

  public var versionString: String {
    return sdkInfo.versionString
  }

  // Returns a target triple that's proper to use with the given SDK path.
  public var targetTriple: String {
    let canonicalName = sdkInfo.canonicalName
    func extractVersion(_ platform: String) -> Substring? {
      if canonicalName.starts(with: platform) {
        let versionStartIndex = canonicalName.index(canonicalName.startIndex,
                                                    offsetBy: platform.count)
        let delimiterRange = canonicalName.range(of: "internal", options: .backwards)
        let versionEndIndex = delimiterRange == nil ? canonicalName.endIndex : delimiterRange!.lowerBound
        return canonicalName[versionStartIndex..<versionEndIndex]
      }
      return nil
    }

    if let version = extractVersion("macosx") {
      return "arm64-apple-macosx\(version)"
    } else if let version = extractVersion("iphoneos") {
      return "arm64-apple-ios\(version)"
    } else if let version = extractVersion("iphonesimulator") {
      return "arm64-apple-ios\(version)-simulator"
    } else if let version = extractVersion("watchos") {
      return "armv7k-apple-watchos\(version)"
    } else if let version = extractVersion("watchsimulator") {
      return "arm64-apple-watchos\(version)-simulator"
    } else if let version = extractVersion("appletvos") {
      return "arm64-apple-tvos\(version)"
    } else if let version = extractVersion("appletvsimulator") {
      return "arm64-apple-tvos\(version)-simulator"
    } else {
      diagEngine.emit(error: "unhandled platform name: \(canonicalName)")
      return ""
    }
  }

  private func sanitizeInterfaceMap(_ map: [String: [PrebuiltModuleInput]]) -> [String: [PrebuiltModuleInput]] {
    return map.filter {
      // Remove modules without associated .swiftinterface files and diagnose.
      if $0.value.isEmpty {
        diagEngine.emit(warning: "\($0.key) has no associated .swiftinterface files")
        return false
      }
      return true
    }
  }

  public func collectSwiftInterfaceMap() throws -> [String: [PrebuiltModuleInput]] {
    var results: [String: [PrebuiltModuleInput]] = [:]

    func updateResults(_ dir: AbsolutePath) throws {
      if !localFileSystem.exists(dir) {
        return
      }
      let moduleName = dir.basenameWithoutExt
      if results[moduleName] == nil {
        results[moduleName] = []
      }

      // Search inside a .swiftmodule directory for any .swiftinterface file, and
      // add the files into the dictionary.
      // Duplicate entries are discarded, otherwise llbuild will complain.
      try localFileSystem.getDirectoryContents(dir).forEach {
        let currentFile = AbsolutePath(dir, try VirtualPath(path: $0).relativePath!)
        if currentFile.extension == "swiftinterface" {
          let currentBaseName = currentFile.basenameWithoutExt
          let interfacePath = TypedVirtualPath(file: VirtualPath.absolute(currentFile).intern(),
                                               type: .swiftInterface)
          if !results[moduleName]!.contains(where: { $0.path.file.basenameWithoutExt == currentBaseName }) {
            results[moduleName]!.append(PrebuiltModuleInput(interfacePath))
          }
        }
        if currentFile.extension == "swiftmodule" {
          diagEngine.emit(warning: "found \(currentFile)")
        }
      }
    }
    // Search inside framework dirs in an SDK to find .swiftmodule directories.
    for dir in frameworkDirs {
      let frameDir = AbsolutePath(sdkPath, dir)
      if !localFileSystem.exists(frameDir) {
        continue
      }
      try localFileSystem.getDirectoryContents(frameDir).forEach {
        let frameworkPath = try VirtualPath(path: $0)
        if frameworkPath.extension != "framework" {
          return
        }
        let moduleName = frameworkPath.basenameWithoutExt
        let swiftModulePath = frameworkPath
          .appending(component: "Modules")
          .appending(component: moduleName + ".swiftmodule").relativePath!
        try updateResults(AbsolutePath(frameDir, swiftModulePath))
      }
    }
    // Search inside lib dirs in an SDK to find .swiftmodule directories.
    for dir in nonFrameworkDirs {
      let swiftModuleDir = AbsolutePath(sdkPath, dir)
      if !localFileSystem.exists(swiftModuleDir) {
        continue
      }
      try localFileSystem.getDirectoryContents(swiftModuleDir).forEach {
        if $0.hasSuffix(".swiftmodule") {
          try updateResults(AbsolutePath(swiftModuleDir, $0))
        }
      }
    }
    return sanitizeInterfaceMap(results)
  }
}

extension Driver {

  private mutating func generateSingleModuleBuildingJob(_ moduleName: String,  _ prebuiltModuleDir: AbsolutePath,
                                                        _ inputPath: PrebuiltModuleInput, _ outputPath: PrebuiltModuleOutput,
                                                        _ dependencies: [TypedVirtualPath]) throws -> Job {
    assert(inputPath.path.file.basenameWithoutExt == outputPath.path.file.basenameWithoutExt)
    var commandLine: [Job.ArgTemplate] = []
    commandLine.appendFlag(.compileModuleFromInterface)
    commandLine.appendFlag(.sdk)
    commandLine.append(.path(sdkPath!))
    commandLine.appendFlag(.prebuiltModuleCachePath)
    commandLine.appendPath(prebuiltModuleDir)
    commandLine.appendFlag(.moduleName)
    commandLine.appendFlag(moduleName)
    commandLine.appendFlag(.o)
    commandLine.appendPath(outputPath.path.file)
    commandLine.appendPath(inputPath.path.file)
    if moduleName == "Swift" {
      commandLine.appendFlag(.parseStdlib)
    }
    // Add macabi-specific search path.
    if isIosMac(inputPath.path.file) {
      commandLine.appendFlag(.Fsystem)
      commandLine.append(.path(iosMacFrameworksSearchPath))
    }
    // Use the specified module cache dir
    if let mcp = parsedOptions.getLastArgument(.moduleCachePath)?.asSingle {
      commandLine.appendFlag(.moduleCachePath)
      commandLine.append(.path(try VirtualPath(path: mcp)))
    }
    commandLine.appendFlag(.serializeParseableModuleInterfaceDependencyHashes)
    commandLine.appendFlag(.badFileDescriptorRetryCount)
    commandLine.appendFlag("30")
    return Job(
      moduleName: moduleName,
      kind: .compile,
      tool: .swiftCompiler,
      commandLine: commandLine,
      inputs: dependencies,
      primaryInputs: [],
      outputs: [outputPath.path]
    )
  }

  public mutating func generatePrebuitModuleGenerationJobs(with inputMap: [String: [PrebuiltModuleInput]],
                                                           into prebuiltModuleDir: AbsolutePath,
                                                           exhaustive: Bool) throws -> ([Job], [Job], AbsolutePath) {
    assert(sdkPath != nil)
    // Run the dependency scanner and update the dependency oracle with the results
    // We only need Swift dependencies here, so we don't need to invoke gatherModuleDependencies,
    // which also resolves versioned clang modules.
    let dependencyGraph = try performDependencyScan()
    var jobs: [Job] = []
    var danglingJobs: [Job] = []
    var inputCount = 0
    // Create directories for each Swift module
    try inputMap.forEach {
      assert(!$0.value.isEmpty)
      try localFileSystem.createDirectory(prebuiltModuleDir
        .appending(RelativePath($0.key + ".swiftmodule")))
    }

    // Generate an outputMap from the inputMap for easy reference.
    let outputMap: [String: [PrebuiltModuleOutput]] =
      Dictionary.init(uniqueKeysWithValues: inputMap.map { key, value in
      let outputPaths: [PrebuiltModuleInput] = value.map {
        let path = prebuiltModuleDir.appending(RelativePath(key + ".swiftmodule"))
          .appending(RelativePath($0.path.file.basenameWithoutExt + ".swiftmodule"))
        return PrebuiltModuleOutput(TypedVirtualPath(file: VirtualPath.absolute(path).intern(),
                                                     type: .swiftModule), $0.arch)
      }
      inputCount += outputPaths.count
      return (key, outputPaths)
    })

    func collectSwiftModuleNames(_ ids: [ModuleDependencyId]) -> [String] {
      return ids.compactMap { id in
        if case .swift(let module) = id {
          return module
        }
        return nil
      }
    }

    func getSwiftDependencies(for module: String) -> [String] {
      let info = dependencyGraph.modules[.swift(module)]!
      guard let dependencies = info.directDependencies else {
        return []
      }
      return collectSwiftModuleNames(dependencies)
    }

    func getOutputPaths(withName modules: [String], loadableFor arch: Triple.Arch) throws -> [TypedVirtualPath] {
      var results: [TypedVirtualPath] = []
      modules.forEach { module in
        guard let allOutputs = outputMap[module] else {
          diagnosticEngine.emit(error: "cannot find output paths for \(module)")
          return
        }
        let allPaths = allOutputs.filter { output in
          if output.arch == arch {
            return true
          }
          // arm64e interfaces can be loded from an arm64 interface but not vice
          // versa.
          if arch == .aarch64 && output.arch == .aarch64e {
            return true
          }
          return false
        }.map { $0.path }
        results.append(contentsOf: allPaths)
      }
      return results
    }

    func forEachInputOutputPair(_ moduleName: String,
                                _ action: (PrebuiltModuleInput, PrebuiltModuleOutput) throws -> ()) throws {
      if let inputPaths = inputMap[moduleName] {
        let outputPaths = outputMap[moduleName]!
        assert(inputPaths.count == outputPaths.count)
        assert(!inputPaths.isEmpty)
        for i in 0..<inputPaths.count {
          let (input, output) = (inputPaths[i], outputPaths[i])
          assert(input.path.file.basenameWithoutExt == output.path.file.basenameWithoutExt)
          try action(input, output)
        }
      }
    }
    // Keep track of modules we haven't handled.
    var unhandledModules = Set<String>(inputMap.keys)
    if let importedModules = dependencyGraph.mainModule.directDependencies {
      // Start from those modules explicitly imported into the file under scanning
      var openModules = collectSwiftModuleNames(importedModules)
      var idx = 0
      while idx != openModules.count {
        let module = openModules[idx]
        let dependencies = getSwiftDependencies(for: module)
        try forEachInputOutputPair(module) { input, output in
          jobs.append(try generateSingleModuleBuildingJob(module,
            prebuiltModuleDir, input, output,
            try getOutputPaths(withName: dependencies, loadableFor: input.arch)))
        }
        // For each dependency, add to the list to handle if the list doesn't
        // contain this dependency.
        dependencies.forEach({ newModule in
          if !openModules.contains(newModule) {
            diagnosticEngine.emit(note: "\(newModule) is discovered.")
            openModules.append(newModule)
          }
        })
        unhandledModules.remove(module)
        idx += 1
      }
    }

    // We are done if we don't need to handle all inputs exhaustively.
    if !exhaustive {
      return (jobs, [], try toolchain.getToolPath(.swiftCompiler))
    }
    // For each unhandled module, generate dangling jobs for each associated
    // interfaces.
    // The only known usage of this so for is in macosx SDK where some collected
    // modules are only for macabi. The file under scanning is using a target triple
    // of mac native so those macabi-only modules cannot be found by the scanner.
    // We have to handle those modules separately without any dependency info.
    try unhandledModules.forEach { moduleName in
      diagnosticEngine.emit(warning: "handle \(moduleName) as dangling jobs")
      try forEachInputOutputPair(moduleName) { input, output in
        danglingJobs.append(try generateSingleModuleBuildingJob(moduleName,
          prebuiltModuleDir, input, output, []))
      }
    }

    // check we've generated jobs for all inputs
    assert(inputCount == jobs.count + danglingJobs.count)
    return (jobs, danglingJobs, try toolchain.getToolPath(.swiftCompiler))
  }
}
