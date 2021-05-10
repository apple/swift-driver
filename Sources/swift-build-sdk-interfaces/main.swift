import SwiftDriverExecution
import SwiftDriver
import TSCLibc
import TSCBasic
import TSCUtility

let diagnosticsEngine = DiagnosticsEngine(handlers: [Driver.stderrDiagnosticsHandler])

guard let sdkPathRaw = ProcessEnv.vars["SDKROOT"] else {
  diagnosticsEngine.emit(.error("need to set SDKROOT"))
  exit(1)
}

func getArgument(_ flag: String) -> String? {
  if let id = CommandLine.arguments.firstIndex(of: flag) {
    let nextId = id.advanced(by: 1)
    if nextId < CommandLine.arguments.count {
      return CommandLine.arguments[nextId]
    }
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
  let sdkPath = try VirtualPath(path: sdkPathRaw).absolutePath!
  if !localFileSystem.exists(sdkPath) {
    diagnosticsEngine.emit(error: "cannot find sdk: \(sdkPath.pathString)")
    exit(1)
  }
  let collector = SDKPrebuiltModuleInputsCollector(sdkPath, diagnosticsEngine)
  var outputDir = try VirtualPath(path: rawOutputDir).absolutePath!
  // if the given output dir ends with 'prebuilt-modules', we should
  // append the SDK version number so all modules will built into
  // the SDK-versioned sub-directory.
  if outputDir.basename == "prebuilt-modules" {
    outputDir = outputDir.appending(RelativePath(collector.versionString))
  }
  if !localFileSystem.exists(outputDir) {
    try localFileSystem.createDirectory(outputDir, recursive: true)
  }
  let swiftcPathRaw = ProcessEnv.vars["SWIFT_EXEC"]
  var swiftcPath: AbsolutePath
  if let swiftcPathRaw = swiftcPathRaw {
    swiftcPath = try VirtualPath(path: swiftcPathRaw).absolutePath!
  } else {
    swiftcPath = sdkPath.parentDirectory.parentDirectory.parentDirectory
      .parentDirectory.parentDirectory.appending(RelativePath("Toolchains"))
      .appending(RelativePath("XcodeDefault.xctoolchain")).appending(RelativePath("usr"))
      .appending(RelativePath("bin")).appending(RelativePath("swiftc"))
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
  let inputMap = try collector.collectSwiftInterfaceMap()
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
                "-sdk", sdkPathRaw]
    let mcpFlag = "-module-cache-path"
    // Append module cache path if given by the client
    if let mcp = getArgument(mcpFlag) {
      args.append(mcpFlag)
      args.append(mcp)
    }
    var driver = try Driver(args: args,
                            diagnosticsEngine: diagnosticsEngine,
                            executor: executor,
                            compilerExecutableDir: swiftcPath.parentDirectory)
    let (jobs, danglingJobs) = try driver.generatePrebuitModuleGenerationJobs(with: inputMap, into: outputDir, exhaustive: !coreMode)
    if verbose {
      Driver.stdErrQueue.sync {
        stderrStream <<< "job count: \(jobs.count + danglingJobs.count)\n"
        stderrStream.flush()
      }
    }
    if skipExecution {
      exit(0)
    }
    let delegate = PrebuitModuleGenerationDelegate(jobs, diagnosticsEngine, verbose)
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
