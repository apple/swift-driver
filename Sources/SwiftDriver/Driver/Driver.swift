//===--------------- Driver.swift - Swift Driver --------------------------===//
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
import SwiftOptions

import class Dispatch.DispatchQueue
import class TSCBasic.DiagnosticsEngine
import class TSCBasic.UnknownLocation
import enum TSCBasic.ProcessEnv
import func TSCBasic.withTemporaryDirectory
import protocol TSCBasic.DiagnosticData
import protocol TSCBasic.FileSystem
import protocol TSCBasic.OutputByteStream
import struct TSCBasic.AbsolutePath
import struct TSCBasic.ByteString
import struct TSCBasic.Diagnostic
import struct TSCBasic.FileInfo
import struct TSCBasic.RelativePath
import var TSCBasic.localFileSystem
import var TSCBasic.stderrStream
import var TSCBasic.stdoutStream

extension Driver {
  /// Stub Error for terminating the process.
  public enum ErrorDiagnostics: Swift.Error {
    case emitted
  }
}

extension Driver.ErrorDiagnostics: CustomStringConvertible {
  public var description: String {
    switch self {
    case .emitted:
      return "errors were encountered"
    }
  }
}


/// The Swift driver.
public struct Driver {
  public enum Error: Swift.Error, Equatable, DiagnosticData {
    case unknownOrMissingSubcommand(String)
    case invalidDriverName(String)
    case invalidInput(String)
    case noInputFiles
    case invalidArgumentValue(String, String)
    case relativeFrontendPath(String)
    case subcommandPassedToDriver
    case integratedReplRemoved
    case cannotSpecify_OForMultipleOutputs
    case conflictingOptions(Option, Option)
    case unableToLoadOutputFileMap(String, String)
    case unableToDecodeFrontendTargetInfo(String?, [String], String)
    case failedToRetrieveFrontendTargetInfo
    case failedToRunFrontendToRetrieveTargetInfo(Int, String?)
    case unableToReadFrontendTargetInfo
    case missingProfilingData(String)
    case conditionalCompilationFlagHasRedundantPrefix(String)
    case conditionalCompilationFlagIsNotValidIdentifier(String)
    case baselineGenerationRequiresTopLevelModule(String)
    case optionRequiresAnother(String, String)
    // Explicit Module Build Failures
    case malformedModuleDependency(String, String)
    case missingPCMArguments(String)
    case missingModuleDependency(String)
    case missingContextHashOnSwiftDependency(String)
    case dependencyScanningFailure(Int, String)
    case missingExternalDependency(String)

    public var description: String {
      switch self {
      case .unknownOrMissingSubcommand(let subcommand):
        return "unknown or missing subcommand '\(subcommand)'"
      case .invalidDriverName(let driverName):
        return "invalid driver name: \(driverName)"
      case .invalidInput(let input):
        return "invalid input: \(input)"
      case .noInputFiles:
        return "no input files"
      case .invalidArgumentValue(let option, let value):
        return "invalid value '\(value)' in '\(option)'"
      case .relativeFrontendPath(let path):
        // TODO: where is this error thrown
        return "relative frontend path: \(path)"
      case .subcommandPassedToDriver:
        return "subcommand passed to driver"
      case .integratedReplRemoved:
        return "Compiler-internal integrated REPL has been removed; use the LLDB-enhanced REPL instead."
      case .cannotSpecify_OForMultipleOutputs:
        return "cannot specify -o when generating multiple output files"
      case .conflictingOptions(let one, let two):
        return "conflicting options '\(one.spelling)' and '\(two.spelling)'"
      case let .unableToDecodeFrontendTargetInfo(outputString, arguments, errorDesc):
        let output = outputString.map { ": \"\($0)\""} ?? ""
        return """
          could not decode frontend target info; compiler driver and frontend executables may be incompatible
          details: frontend: \(arguments.first ?? "")
                   arguments: \(arguments.dropFirst())
                   error: \(errorDesc)
          output\n\(output)
          """
      case .failedToRetrieveFrontendTargetInfo:
        return "failed to retrieve frontend target info"
      case .unableToReadFrontendTargetInfo:
        return "could not read frontend target info"
      case let .failedToRunFrontendToRetrieveTargetInfo(returnCode, stderr):
        return "frontend job retrieving target info failed with code \(returnCode)"
          + (stderr.map {": \($0)"} ?? "")
      case .missingProfilingData(let arg):
        return "no profdata file exists at '\(arg)'"
      case .conditionalCompilationFlagHasRedundantPrefix(let name):
        return "invalid argument '-D\(name)'; did you provide a redundant '-D' in your build settings?"
      case .conditionalCompilationFlagIsNotValidIdentifier(let name):
        return "conditional compilation flags must be valid Swift identifiers (rather than '\(name)')"
      // Explicit Module Build Failures
      case .malformedModuleDependency(let moduleName, let errorDescription):
        return "Malformed Module Dependency: \(moduleName), \(errorDescription)"
      case .missingPCMArguments(let moduleName):
        return "Missing extraPcmArgs to build Clang module: \(moduleName)"
      case .missingModuleDependency(let moduleName):
        return "Missing Module Dependency Info: \(moduleName)"
      case .missingContextHashOnSwiftDependency(let moduleName):
        return "Missing Context Hash for Swift dependency: \(moduleName)"
      case .dependencyScanningFailure(let code, let error):
        return "Module Dependency Scanner returned with non-zero exit status: \(code), \(error)"
      case .unableToLoadOutputFileMap(let path, let error):
        return "unable to load output file map '\(path)': \(error)"
      case .missingExternalDependency(let moduleName):
        return "Missing External dependency info for module: \(moduleName)"
      case .baselineGenerationRequiresTopLevelModule(let arg):
        return "generating a baseline with '\(arg)' is only supported with '-emit-module' or '-emit-module-path'"
      case .optionRequiresAnother(let first, let second):
        return "'\(first)' cannot be specified if '\(second)' is not present"
      }
    }
  }

  /// Specific implementation of a diagnostics output type that can be used when initializing a new `Driver`.
  public enum DiagnosticsOutput {
    case engine(DiagnosticsEngine)
    case handler(DiagnosticsEngine.DiagnosticsHandler)
  }

  /// The set of environment variables that are visible to the driver and
  /// processes it launches. This is a hook for testing; in actual use
  /// it should be identical to the real environment.
  public let env: [String: String]

  /// Whether we are using the driver as the integrated driver via libSwiftDriver
  public let integratedDriver: Bool

  /// The file system which we should interact with.
  @_spi(Testing) public let fileSystem: FileSystem

  /// Diagnostic engine for emitting warnings, errors, etc.
  public let diagnosticEngine: DiagnosticsEngine

  /// The executor the driver uses to run jobs.
  let executor: DriverExecutor

  /// The toolchain to use for resolution.
  @_spi(Testing) public let toolchain: Toolchain

  /// Information about the target, as reported by the Swift frontend.
  @_spi(Testing) public let frontendTargetInfo: FrontendTargetInfo

  /// The target triple.
  @_spi(Testing) public var targetTriple: Triple { frontendTargetInfo.target.triple }

  /// The host environment triple.
  @_spi(Testing) public let hostTriple: Triple

  /// The variant target triple.
  var targetVariantTriple: Triple? {
    frontendTargetInfo.targetVariant?.triple
  }

  /// `true` if the driver should use the static resource directory.
  let useStaticResourceDir: Bool

  /// The kind of driver.
  let driverKind: DriverKind

  /// The option table we're using.
  let optionTable: OptionTable

  /// The set of parsed options.
  var parsedOptions: ParsedOptions

  /// Whether to print out extra info regarding jobs
  let showJobLifecycle: Bool

  /// Extra command-line arguments to pass to the Swift compiler.
  let swiftCompilerPrefixArgs: [String]

  /// The working directory for the driver, if there is one.
  let workingDirectory: AbsolutePath?

  /// The set of input files
  @_spi(Testing) public let inputFiles: [TypedVirtualPath]

  /// The last time each input file was modified, recorded at the start of the build.
  @_spi(Testing) public let recordedInputModificationDates: [TypedVirtualPath: TimePoint]

  /// The mapping from input files to output files for each kind.
  let outputFileMap: OutputFileMap?

  /// The number of files required before making a file list.
  let fileListThreshold: Int

  /// Should use file lists for inputs (number of inputs exceeds `fileListThreshold`).
  let shouldUseInputFileList: Bool

  /// VirtualPath for shared all sources file list. `nil` if unused. This is used as a cache for
  /// the file list computed during CompileJob creation and only holds valid to be query by tests
  /// after planning to build.
  @_spi(Testing) public var allSourcesFileList: VirtualPath? = nil

  /// The mode in which the compiler will execute.
  @_spi(Testing) public let compilerMode: CompilerMode

  /// A distinct job will build the module files.
  @_spi(Testing) public let emitModuleSeparately: Bool

  /// The type of the primary output generated by the compiler.
  @_spi(Testing) public let compilerOutputType: FileType?

  /// The type of the link-time-optimization we expect to perform.
  @_spi(Testing) public let lto: LTOKind?

  /// The type of the primary output generated by the linker.
  @_spi(Testing) public let linkerOutputType: LinkOutputType?

  /// When > 0, the number of threads to use in a multithreaded build.
  @_spi(Testing) public let numThreads: Int

  /// The specified maximum number of parallel jobs to execute.
  @_spi(Testing) public let numParallelJobs: Int?

  /// The set of sanitizers that were requested
  let enabledSanitizers: Set<Sanitizer>

  /// The debug information to produce.
  @_spi(Testing) public let debugInfo: DebugInfo

  /// The information about the module to produce.
  @_spi(Testing) public let moduleOutputInfo: ModuleOutputInfo

  /// Name of the package containing a target module or file.
  @_spi(Testing) public let packageName: String?

  /// Info needed to write and maybe read the build record.
  /// Only present when the driver will be writing the record.
  /// Only used for reading when compiling incrementally.
  @_spi(Testing) public let buildRecordInfo: BuildRecordInfo?

  /// Whether to consider incremental compilation.
  let shouldAttemptIncrementalCompilation: Bool

  /// CAS/Caching related options.
  let enableCaching: Bool
  let useClangIncludeTree: Bool

  /// CAS instance used for compilation.
  @_spi(Testing) public var cas: SwiftScanCAS? = nil

  /// Is swift caching enabled.
  lazy var isCachingEnabled: Bool = {
    return enableCaching && isFeatureSupported(.compilation_caching)
  }()

  /// Scanner prefix mapping.
  let scannerPrefixMap: [AbsolutePath: AbsolutePath]
  let scannerPrefixMapSDK: AbsolutePath?
  let scannerPrefixMapToolchain: AbsolutePath?
  lazy var prefixMapping: [(AbsolutePath, AbsolutePath)] = {
    var mapping: [(AbsolutePath, AbsolutePath)] = scannerPrefixMap.map {
      return ($0.key, $0.value)
    }
    do {
      guard isFrontendArgSupported(.scannerPrefixMap) else {
        return []
      }
      if let sdkMapping = scannerPrefixMapSDK,
         let sdkPath = absoluteSDKPath {
        mapping.append((sdkPath, sdkMapping))
      }
      if let toolchainMapping = scannerPrefixMapToolchain {
        let toolchainPath = try toolchain.executableDir.parentDirectory // usr
                                                       .parentDirectory // toolchain
        mapping.append((toolchainPath, toolchainMapping))
      }
      // The mapping needs to be sorted so the mapping is determinisitic.
      // The sorting order is reversed so /tmp/tmp is preferred over /tmp in remapping.
      return mapping.sorted { $0.0 > $1.0 }
    } catch {
      return mapping.sorted { $0.0 > $1.0 }
    }
  }()

  /// Code & data for incremental compilation. Nil if not running in incremental mode.
  /// Set during planning because needs the jobs to look at outputs.
  @_spi(Testing) public private(set) var incrementalCompilationState: IncrementalCompilationState? = nil

  /// Nil if not running in explicit module build mode.
  /// Set during planning.
  var interModuleDependencyGraph: InterModuleDependencyGraph? = nil

  /// The path of the SDK.
  public var absoluteSDKPath: AbsolutePath? {
    guard let path = frontendTargetInfo.sdkPath?.path else {
      return nil
    }

    switch VirtualPath.lookup(path) {
    case .absolute(let path):
      return path
    case .relative(let path):
      return workingDirectory.map { AbsolutePath($0, path) }
    case .standardInput, .standardOutput, .temporary, .temporaryWithKnownContents, .fileList:
      fatalError("Frontend target information will never include a path of this type.")
    }
  }

  /// The path to the imported Objective-C header.
  let importedObjCHeader: VirtualPath.Handle?

  /// The path to the pch for the imported Objective-C header.
  lazy var bridgingPrecompiledHeader: VirtualPath.Handle? = {
    let contextHash = try? explicitDependencyBuildPlanner?.getMainModuleContextHash()
    return Self.computeBridgingPrecompiledHeader(&parsedOptions,
                                                 compilerMode: compilerMode,
                                                 importedObjCHeader: importedObjCHeader,
                                                 outputFileMap: outputFileMap,
                                                 contextHash: contextHash)
  }()

  /// Path to the dependencies file.
  let dependenciesFilePath: VirtualPath.Handle?

  /// Path to the references dependencies file.
  let referenceDependenciesPath: VirtualPath.Handle?

  /// Path to the serialized diagnostics file.
  let serializedDiagnosticsFilePath: VirtualPath.Handle?

  /// Path to the serialized diagnostics file of the emit-module task.
  let emitModuleSerializedDiagnosticsFilePath: VirtualPath.Handle?

  /// Path to the discovered dependencies file of the emit-module task.
  let emitModuleDependenciesFilePath: VirtualPath.Handle?

  /// Path to emitted compile-time-known values.
  let constValuesFilePath: VirtualPath.Handle?

  /// Path to the Objective-C generated header.
  let objcGeneratedHeaderPath: VirtualPath.Handle?

  /// Path to the loaded module trace file.
  let loadedModuleTracePath: VirtualPath.Handle?

  /// Path to the TBD file (text-based dylib).
  let tbdPath: VirtualPath.Handle?

  /// Path to the module documentation file.
  let moduleDocOutputPath: VirtualPath.Handle?

  /// Path to the Swift interface file.
  let swiftInterfacePath: VirtualPath.Handle?

  /// Path to the Swift private interface file.
  let swiftPrivateInterfacePath: VirtualPath.Handle?

  /// Path to the Swift package interface file.
  let swiftPackageInterfacePath: VirtualPath.Handle?

  /// File type for the optimization record.
  let optimizationRecordFileType: FileType?

  /// Path to the optimization record.
  let optimizationRecordPath: VirtualPath.Handle?

  /// Path to the Swift module source information file.
  let moduleSourceInfoPath: VirtualPath.Handle?

  /// Path to the module's digester baseline file.
  let digesterBaselinePath: VirtualPath.Handle?

  /// Path to the emitted API descriptor file.
  let apiDescriptorFilePath: VirtualPath.Handle?

  /// The mode the API digester should run in.
  let digesterMode: DigesterMode

  // FIXME: We should soon be able to remove this from being in the Driver's state.
  // Its only remaining use outside of actual dependency build planning is in
  // command-line input option generation for the explicit main module compile job.
  /// Planner for constructing module build jobs using Explicit Module Builds.
  /// Constructed during the planning phase only when all module dependencies will be prebuilt and treated
  /// as explicit inputs by the various compilation jobs.
  @_spi(Testing) public var explicitDependencyBuildPlanner: ExplicitDependencyBuildPlanner? = nil

  /// An oracle for querying inter-module dependencies
  /// Can either be an argument to the driver in many-module contexts where dependency information
  /// is shared across many targets; otherwise, a new instance is created by the driver itself.
  @_spi(Testing) public let interModuleDependencyOracle: InterModuleDependencyOracle

  /// A dictionary of external targets that are a part of the same build, mapping to filesystem paths
  /// of their module files
  @_spi(Testing) public var externalTargetModuleDetailsMap: ExternalTargetModuleDetailsMap? = nil

  /// A collection of all the flags the selected toolchain's `swift-frontend` supports
  public let supportedFrontendFlags: Set<String>

  /// A list of unknown driver flags that are recognizable to `swift-frontend`
  public let savedUnknownDriverFlagsForSwiftFrontend: [String]

  /// A collection of all the features the selected toolchain's `swift-frontend` supports
  public let supportedFrontendFeatures: Set<String>

  /// A global queue for emitting non-interrupted messages into stderr
  public static let stdErrQueue = DispatchQueue(label: "org.swift.driver.emit-to-stderr")

  @_spi(Testing)
  public enum KnownCompilerFeature: String {
    case emit_abi_descriptor = "emit-abi-descriptor"
    case compilation_caching = "compilation-caching"
  }

  lazy var sdkPath: VirtualPath? = {
    guard let rawSdkPath = frontendTargetInfo.sdkPath?.path else {
      return nil
    }
    return VirtualPath.lookup(rawSdkPath)
  } ()

  lazy var iosMacFrameworksSearchPath: VirtualPath = {
    sdkPath!
      .appending(component: "System")
      .appending(component: "iOSSupport")
      .appending(component: "System")
      .appending(component: "Library")
      .appending(component: "Frameworks")
  } ()

  lazy var abiDescriptorPath: TypedVirtualPath? = {
    guard isFeatureSupported(.emit_abi_descriptor) else {
      return nil
    }
    // Emit the descriptor only on platforms where Library Evolution is supported,
    // or opted-into explicitly.
    guard targetTriple.isDarwin || parsedOptions.hasArgument(.enableLibraryEvolution) else {
      return nil
    }
    guard let moduleOutput = moduleOutputInfo.output else {
      return nil
    }
    guard let path = try? VirtualPath.lookup(moduleOutput.outputPath).replacingExtension(with: .jsonABIBaseline) else {
      return nil
    }
    return TypedVirtualPath(file: path.intern(), type: .jsonABIBaseline)
  }()

  public static func isOptionFound(_ opt: String, allOpts: Set<String>) -> Bool {
    var current = opt
    while(true) {
      if allOpts.contains(current) {
        return true
      }
      if current.starts(with: "-") {
        current = String(current.dropFirst())
      } else {
        return false
      }
    }
  }

  public func isFrontendArgSupported(_ opt: Option) -> Bool {
    return Driver.isOptionFound(opt.spelling, allOpts: supportedFrontendFlags)
  }

  @_spi(Testing)
  public func isFeatureSupported(_ feature: KnownCompilerFeature) -> Bool {
    return supportedFrontendFeatures.contains(feature.rawValue)
  }

  public func getSwiftScanLibPath() throws -> AbsolutePath? {
    return try toolchain.lookupSwiftScanLib()
  }

  @_spi(Testing)
  public static func findBlocklists(RelativeTo execDir: AbsolutePath) throws ->  [AbsolutePath] {
    // Expect to find all blocklists in such dir:
    // .../XcodeDefault.xctoolchain/usr/local/lib/swift/blocklists
    var results: [AbsolutePath] = []
    let blockListDir = execDir.parentDirectory
      .appending(components: "local", "lib", "swift", "blocklists")
    if (localFileSystem.exists(blockListDir)) {
      try localFileSystem.getDirectoryContents(blockListDir).forEach {
        let currentFile = AbsolutePath(blockListDir, try VirtualPath(path: $0).relativePath!)
        if currentFile.extension == "yml" || currentFile.extension == "yaml" {
          results.append(currentFile)
        }
      }
    }
    return results
  }

  @_spi(Testing)
  public static func findCompilerClientsConfigVersion(RelativeTo execDir: AbsolutePath) throws -> String? {
    // Expect to find all blocklists in such dir:
    // .../XcodeDefault.xctoolchain/usr/local/lib/swift/compilerClientsConfig_version.txt
    let versionFilePath = execDir.parentDirectory
      .appending(components: "local", "lib", "swift", "compilerClientsConfig_version.txt")
    if (localFileSystem.exists(versionFilePath)) {
      return try localFileSystem.readFileContents(versionFilePath).cString
    }
    return nil
  }

  /// Handler for emitting diagnostics to stderr.
  public static let stderrDiagnosticsHandler: DiagnosticsEngine.DiagnosticsHandler = { diagnostic in
    stdErrQueue.sync {
      let stream = stderrStream
      if !(diagnostic.location is UnknownLocation) {
          stream.send("\(diagnostic.location.description): ")
      }

      switch diagnostic.message.behavior {
      case .error:
        stream.send("error: ")
      case .warning:
        stream.send("warning: ")
      case .note:
        stream.send("note: ")
      case .remark:
        stream.send("remark: ")
      case .ignored:
          break
      }

      stream.send("\(diagnostic.localizedDescription)\n")
      stream.flush()
    }
  }

  @available(*, deprecated, renamed: "init(args:env:diagnosticsOutput:fileSystem:executor:integratedDriver:compilerExecutableDir:externalTargetModuleDetailsMap:interModuleDependencyOracle:)")
  public init(
    args: [String],
    env: [String: String] = ProcessEnv.vars,
    diagnosticsEngine: DiagnosticsEngine,
    fileSystem: FileSystem = localFileSystem,
    executor: DriverExecutor,
    integratedDriver: Bool = true,
    compilerExecutableDir: AbsolutePath? = nil,
    externalTargetModuleDetailsMap: ExternalTargetModuleDetailsMap? = nil,
    interModuleDependencyOracle: InterModuleDependencyOracle? = nil
  ) throws {
    try self.init(
      args: args,
      env: env,
      diagnosticsOutput: .engine(diagnosticsEngine),
      fileSystem: fileSystem,
      executor: executor,
      integratedDriver: integratedDriver,
      compilerExecutableDir: compilerExecutableDir,
      externalTargetModuleDetailsMap: externalTargetModuleDetailsMap,
      interModuleDependencyOracle: interModuleDependencyOracle
    )
  }

  /// Create the driver with the given arguments.
  ///
  /// - Parameter args: The command-line arguments, including the "swift" or "swiftc"
  ///   at the beginning.
  /// - Parameter env: The environment variables to use. This is a hook for testing;
  ///   in production, you should use the default argument, which copies the current environment.
  /// - Parameter diagnosticsOutput: The diagnostics output implementation used by the driver to emit errors
  ///   and warnings.
  /// - Parameter fileSystem: The filesystem used by the driver to find resources/SDKs,
  ///   expand response files, etc. By default this is the local filesystem.
  /// - Parameter executor: Used by the driver to execute jobs. The default argument
  ///   is present to streamline testing, it shouldn't be used in production.
  /// - Parameter integratedDriver: Used to distinguish whether the driver is being used as
  ///   an executable or as a library.
  /// - Parameter compilerExecutableDir: Directory that contains the compiler executable to be used.
  ///   Used when in `integratedDriver` mode as a substitute for the driver knowing its executable path.
  /// - Parameter externalTargetModuleDetailsMap: A dictionary of external targets that are a part of
  ///   the same build, mapping to a details value which includes a filesystem path of their
  ///   `.swiftmodule` and a flag indicating whether the external target is a framework.
  /// - Parameter interModuleDependencyOracle: An oracle for querying inter-module dependencies,
  ///   shared across different module builds by a build system.
  public init(
    args: [String],
    env: [String: String] = ProcessEnv.vars,
    diagnosticsOutput: DiagnosticsOutput = .engine(DiagnosticsEngine(handlers: [Driver.stderrDiagnosticsHandler])),
    fileSystem: FileSystem = localFileSystem,
    executor: DriverExecutor,
    integratedDriver: Bool = true,
    compilerExecutableDir: AbsolutePath? = nil,
    externalTargetModuleDetailsMap: ExternalTargetModuleDetailsMap? = nil,
    interModuleDependencyOracle: InterModuleDependencyOracle? = nil
  ) throws {
    self.env = env
    self.fileSystem = fileSystem
    self.integratedDriver = integratedDriver

    let diagnosticsEngine: DiagnosticsEngine
    switch diagnosticsOutput {
    case .engine(let engine):
      diagnosticsEngine = engine
    case .handler(let handler):
      diagnosticsEngine = DiagnosticsEngine(handlers: [handler])
    }
    self.diagnosticEngine = diagnosticsEngine

    self.executor = executor
    self.externalTargetModuleDetailsMap = externalTargetModuleDetailsMap

    if case .subcommand = try Self.invocationRunMode(forArgs: args).mode {
      throw Error.subcommandPassedToDriver
    }
    var args = args
    if let additional = env["ADDITIONAL_SWIFT_DRIVER_FLAGS"] {
      args.append(contentsOf: additional.components(separatedBy: " "))
    }

    args = try Self.expandResponseFiles(args, fileSystem: fileSystem, diagnosticsEngine: self.diagnosticEngine)

    self.driverKind = try Self.determineDriverKind(args: &args)
    self.optionTable = OptionTable()
    self.parsedOptions = try optionTable.parse(Array(args), for: self.driverKind, delayThrows: true)
    self.showJobLifecycle = parsedOptions.contains(.driverShowJobLifecycle)

    // Determine the compilation mode.
    self.compilerMode = try Self.computeCompilerMode(&parsedOptions, driverKind: driverKind, diagnosticsEngine: diagnosticEngine)

    self.shouldAttemptIncrementalCompilation = Self.shouldAttemptIncrementalCompilation(&parsedOptions,
                                                                                        diagnosticEngine: diagnosticsEngine,
                                                                                        compilerMode: compilerMode)

    // Compute the working directory.
    let cwd = fileSystem.currentWorkingDirectory
    workingDirectory = try parsedOptions.getLastArgument(.workingDirectory).map { workingDirectoryArg in
      return try cwd.map{ try AbsolutePath(validating: workingDirectoryArg.asSingle, relativeTo: $0) } ?? AbsolutePath(validating: workingDirectoryArg.asSingle)
    } ?? cwd

    // Apply the working directory to the parsed options.
    if let workingDirectory = self.workingDirectory {
      try Self.applyWorkingDirectory(workingDirectory, to: &self.parsedOptions)
    }

    let staticExecutable = parsedOptions.hasFlag(positive: .staticExecutable,
                                                 negative: .noStaticExecutable,
                                                 default: false)
    let staticStdlib = parsedOptions.hasFlag(positive: .staticStdlib,
                                             negative: .noStaticStdlib,
                                             default: false)
    self.useStaticResourceDir = staticExecutable || staticStdlib

    // Build the toolchain and determine target information.
    (self.toolchain, self.frontendTargetInfo, self.swiftCompilerPrefixArgs) =
        try Self.computeToolchain(
          &self.parsedOptions, diagnosticsEngine: diagnosticEngine,
          compilerMode: self.compilerMode, env: env,
          executor: self.executor, fileSystem: fileSystem,
          useStaticResourceDir: self.useStaticResourceDir,
          workingDirectory: self.workingDirectory,
          compilerExecutableDir: compilerExecutableDir)

    // Compute the host machine's triple
    self.hostTriple =
      try Self.computeHostTriple(&self.parsedOptions, diagnosticsEngine: diagnosticEngine,
                                 toolchain: self.toolchain, executor: self.executor,
                                 fileSystem: fileSystem,
                                 workingDirectory: self.workingDirectory,
                                 swiftCompilerPrefixArgs: self.swiftCompilerPrefixArgs)

    // Classify and collect all of the input files.
    let inputFiles = try Self.collectInputFiles(&self.parsedOptions, diagnosticsEngine: diagnosticsEngine, fileSystem: self.fileSystem)
    self.inputFiles = inputFiles
    self.recordedInputModificationDates = .init(uniqueKeysWithValues:
      Set(inputFiles).compactMap {
        guard let modTime = try? fileSystem
          .lastModificationTime(for: $0.file) else { return nil }
        return ($0, modTime)
    })

    do {
      let outputFileMap: OutputFileMap?
      // Initialize an empty output file map, which will be populated when we start creating jobs.
      if let outputFileMapArg = parsedOptions.getLastArgument(.outputFileMap)?.asSingle {
        do {
          let path = try VirtualPath(path: outputFileMapArg)
          outputFileMap = try .load(fileSystem: fileSystem, file: path, diagnosticEngine: diagnosticEngine)
        } catch let error {
          throw Error.unableToLoadOutputFileMap(outputFileMapArg, error.localizedDescription)
        }
      } else {
        outputFileMap = nil
      }

      if let workingDirectory = self.workingDirectory {
        self.outputFileMap = outputFileMap?.resolveRelativePaths(relativeTo: workingDirectory)
      } else {
        self.outputFileMap = outputFileMap
      }
    }

    // Create an instance of an inter-module dependency oracle, if the driver's
    // client did not provide one. The clients are expected to provide an oracle
    // when they wish to share module dependency information across targets.
    if let dependencyOracle = interModuleDependencyOracle {
      self.interModuleDependencyOracle = dependencyOracle
    } else {
      self.interModuleDependencyOracle = InterModuleDependencyOracle()
    }

    self.fileListThreshold = try Self.computeFileListThreshold(&self.parsedOptions, diagnosticsEngine: diagnosticsEngine)
    self.shouldUseInputFileList = inputFiles.count > fileListThreshold

    self.lto = Self.ltoKind(&parsedOptions, diagnosticsEngine: diagnosticsEngine)
    // Figure out the primary outputs from the driver.
    (self.compilerOutputType, self.linkerOutputType) = 
      Self.determinePrimaryOutputs(&parsedOptions, targetTriple: self.frontendTargetInfo.target.triple, 
                                   driverKind: driverKind, diagnosticsEngine: diagnosticEngine)

    // Multithreading.
    self.numThreads = Self.determineNumThreads(&parsedOptions, compilerMode: compilerMode, diagnosticsEngine: diagnosticEngine)
    self.numParallelJobs = Self.determineNumParallelJobs(&parsedOptions, diagnosticsEngine: diagnosticEngine, env: env)

    var mode = DigesterMode.api
    if let modeArg = parsedOptions.getLastArgument(.digesterMode)?.asSingle {
      if let digesterMode = DigesterMode(rawValue: modeArg) {
        mode = digesterMode
      } else {
        diagnosticsEngine.emit(.error(Error.invalidArgumentValue(Option.digesterMode.spelling, modeArg)),
                               location: nil)
      }
    }
    self.digesterMode = mode

    Self.validateWarningControlArgs(&parsedOptions, diagnosticEngine: diagnosticEngine)
    Self.validateProfilingArgs(&parsedOptions,
                               fileSystem: fileSystem,
                               workingDirectory: workingDirectory,
                               diagnosticEngine: diagnosticEngine)
    Self.validateEmitDependencyGraphArgs(&parsedOptions, diagnosticEngine: diagnosticEngine)
    Self.validateValidateClangModulesOnceOptions(&parsedOptions, diagnosticEngine: diagnosticEngine)
    Self.validateParseableOutputArgs(&parsedOptions, diagnosticEngine: diagnosticEngine)
    Self.validateCompilationConditionArgs(&parsedOptions, diagnosticEngine: diagnosticEngine)
    Self.validateFrameworkSearchPathArgs(&parsedOptions, diagnosticEngine: diagnosticEngine)
    Self.validateCoverageArgs(&parsedOptions, diagnosticsEngine: diagnosticEngine)
    Self.validateLinkArgs(&parsedOptions, diagnosticsEngine: diagnosticEngine)
    try toolchain.validateArgs(&parsedOptions,
                               targetTriple: self.frontendTargetInfo.target.triple,
                               targetVariantTriple: self.frontendTargetInfo.targetVariant?.triple,
                               compilerOutputType: self.compilerOutputType,
                               diagnosticsEngine: diagnosticEngine)

    // Compute debug information output.
    let defaultDwarfVersion = self.toolchain.getDefaultDwarfVersion(targetTriple: self.frontendTargetInfo.target.triple)
    self.debugInfo = Self.computeDebugInfo(&parsedOptions,
                                           defaultDwarfVersion: defaultDwarfVersion,
                                           diagnosticsEngine: diagnosticEngine)

    // Error if package-name is passed but the input is empty; if
    // package-name is not passed but `package` decls exist, error
    // will occur during the frontend type check.
    self.packageName = parsedOptions.getLastArgument(.packageName)?.asSingle
    if let packageName = packageName, packageName.isEmpty {
      diagnosticsEngine.emit(.error_empty_package_name)
    }

    // Determine the module we're building and whether/how the module file itself will be emitted.
    self.moduleOutputInfo = try Self.computeModuleInfo(
      &parsedOptions, compilerOutputType: compilerOutputType, compilerMode: compilerMode, linkerOutputType: linkerOutputType,
      debugInfoLevel: debugInfo.level, diagnosticsEngine: diagnosticEngine,
      workingDirectory: self.workingDirectory)

    // Should we schedule a separate emit-module job?
    self.emitModuleSeparately = Self.computeEmitModuleSeparately(parsedOptions: &parsedOptions,
                                                                 compilerMode: compilerMode,
                                                                 compilerOutputType: compilerOutputType,
                                                                 moduleOutputInfo: moduleOutputInfo,
                                                                 inputFiles: inputFiles)

    self.buildRecordInfo = BuildRecordInfo(
      actualSwiftVersion: self.frontendTargetInfo.compilerVersion,
      compilerOutputType: compilerOutputType,
      workingDirectory: self.workingDirectory,
      diagnosticEngine: diagnosticEngine,
      fileSystem: fileSystem,
      moduleOutputInfo: moduleOutputInfo,
      outputFileMap: outputFileMap,
      incremental: self.shouldAttemptIncrementalCompilation,
      parsedOptions: parsedOptions,
      recordedInputModificationDates: recordedInputModificationDates)

    self.importedObjCHeader = try Self.computeImportedObjCHeader(&parsedOptions, compilerMode: compilerMode, diagnosticEngine: diagnosticEngine)

    self.supportedFrontendFlags =
      try Self.computeSupportedCompilerArgs(of: self.toolchain,
                                            parsedOptions: &self.parsedOptions,
                                            diagnosticsEngine: diagnosticEngine,
                                            fileSystem: fileSystem,
                                            executor: executor)
    let supportedFrontendFlagsLocal = self.supportedFrontendFlags
    self.savedUnknownDriverFlagsForSwiftFrontend = try self.parsedOptions.saveUnknownFlags {
      Driver.isOptionFound($0, allOpts: supportedFrontendFlagsLocal)
    }
    self.savedUnknownDriverFlagsForSwiftFrontend.forEach {
      diagnosticsEngine.emit(.warning("save unknown driver flag \($0) as additional swift-frontend flag"),
                             location: nil)
    }
    self.supportedFrontendFeatures = try Self.computeSupportedCompilerFeatures(of: self.toolchain, env: env)

    // Caching options.
    let cachingEnabled = parsedOptions.hasArgument(.cacheCompileJob) || env.keys.contains("SWIFT_ENABLE_CACHING")
    if cachingEnabled {
      if !parsedOptions.hasArgument(.driverExplicitModuleBuild) {
        diagnosticsEngine.emit(.warning("-cache-compile-job cannot be used without explicit module build, turn off caching"),
                               location: nil)
        self.enableCaching = false
      } else if importedObjCHeader != nil, !parsedOptions.hasFlag(positive: .enableBridgingPch, negative: .disableBridgingPch, default: true) {
        diagnosticsEngine.emit(.warning("-cache-compile-job cannot be used with -disable-bridging-pch, turn off caching"),
                               location: nil)
        self.enableCaching = false
      } else {
        self.enableCaching = true
      }
    } else {
      self.enableCaching = false
    }
    self.useClangIncludeTree = !parsedOptions.hasArgument(.noClangIncludeTree) && !env.keys.contains("SWIFT_CACHING_USE_CLANG_CAS_FS")
    self.scannerPrefixMap = try Self.computeScanningPrefixMapper(&parsedOptions)
    if let sdkMapping =  parsedOptions.getLastArgument(.scannerPrefixMapSdk)?.asSingle {
      self.scannerPrefixMapSDK = try AbsolutePath(validating: sdkMapping)
    } else {
      self.scannerPrefixMapSDK = nil
    }
    if let toolchainMapping = parsedOptions.getLastArgument(.scannerPrefixMapToolchain)?.asSingle {
      self.scannerPrefixMapToolchain = try AbsolutePath(validating: toolchainMapping)
    } else {
      self.scannerPrefixMapToolchain = nil
    }

    self.enabledSanitizers = try Self.parseSanitizerArgValues(
      &parsedOptions,
      diagnosticEngine: diagnosticEngine,
      toolchain: toolchain,
      targetInfo: frontendTargetInfo)

    Self.validateSanitizerAddressUseOdrIndicatorFlag(&parsedOptions, diagnosticEngine: diagnosticsEngine, addressSanitizerEnabled: enabledSanitizers.contains(.address))

    Self.validateSanitizeStableABI(&parsedOptions, diagnosticEngine: diagnosticsEngine, addressSanitizerEnabled: enabledSanitizers.contains(.address))

    Self.validateSanitizerRecoverArgValues(&parsedOptions, diagnosticEngine: diagnosticsEngine, enabledSanitizers: enabledSanitizers)

    Self.validateSanitizerCoverageArgs(&parsedOptions,
                                       anySanitizersEnabled: !enabledSanitizers.isEmpty,
                                       diagnosticsEngine: diagnosticsEngine)

    // Supplemental outputs.
    self.dependenciesFilePath = try Self.computeSupplementaryOutputPath(
        &parsedOptions, type: .dependencies, isOutputOptions: [.emitDependencies],
        outputPath: .emitDependenciesPath,
        compilerOutputType: compilerOutputType,
        compilerMode: compilerMode,
        emitModuleSeparately: emitModuleSeparately,
        outputFileMap: self.outputFileMap,
        moduleName: moduleOutputInfo.name)
    self.referenceDependenciesPath = try Self.computeSupplementaryOutputPath(
        &parsedOptions, type: .swiftDeps, isOutputOptions: shouldAttemptIncrementalCompilation ? [.incremental] : [],
        outputPath: .emitReferenceDependenciesPath,
        compilerOutputType: compilerOutputType,
        compilerMode: compilerMode,
        emitModuleSeparately: emitModuleSeparately,
        outputFileMap: self.outputFileMap,
        moduleName: moduleOutputInfo.name)
    self.serializedDiagnosticsFilePath = try Self.computeSupplementaryOutputPath(
        &parsedOptions, type: .diagnostics, isOutputOptions: [.serializeDiagnostics],
        outputPath: .serializeDiagnosticsPath,
        compilerOutputType: compilerOutputType,
        compilerMode: compilerMode,
        emitModuleSeparately: emitModuleSeparately,
        outputFileMap: self.outputFileMap,
        moduleName: moduleOutputInfo.name)
    self.emitModuleSerializedDiagnosticsFilePath = try Self.computeSupplementaryOutputPath(
        &parsedOptions, type: .emitModuleDiagnostics, isOutputOptions: [.serializeDiagnostics],
        outputPath: .emitModuleSerializeDiagnosticsPath,
        compilerOutputType: compilerOutputType,
        compilerMode: compilerMode,
        emitModuleSeparately: emitModuleSeparately,
        outputFileMap: self.outputFileMap,
        moduleName: moduleOutputInfo.name)
    self.emitModuleDependenciesFilePath = try Self.computeSupplementaryOutputPath(
        &parsedOptions, type: .emitModuleDependencies, isOutputOptions: [.emitDependencies],
        outputPath: .emitModuleDependenciesPath,
        compilerOutputType: compilerOutputType,
        compilerMode: compilerMode,
        emitModuleSeparately: emitModuleSeparately,
        outputFileMap: self.outputFileMap,
        moduleName: moduleOutputInfo.name)
    self.constValuesFilePath = try Self.computeSupplementaryOutputPath(
        &parsedOptions, type: .swiftConstValues, isOutputOptions: [.emitConstValues],
        outputPath: .emitConstValuesPath,
        compilerOutputType: compilerOutputType,
        compilerMode: compilerMode,
        emitModuleSeparately: emitModuleSeparately,
        outputFileMap: self.outputFileMap,
        moduleName: moduleOutputInfo.name)
    // FIXME: -fixits-output-path
    self.objcGeneratedHeaderPath = try Self.computeSupplementaryOutputPath(
        &parsedOptions, type: .objcHeader, isOutputOptions: [.emitObjcHeader],
        outputPath: .emitObjcHeaderPath,
        compilerOutputType: compilerOutputType,
        compilerMode: compilerMode,
        emitModuleSeparately: emitModuleSeparately,
        outputFileMap: self.outputFileMap,
        moduleName: moduleOutputInfo.name)

    if let loadedModuleTraceEnvVar = env["SWIFT_LOADED_MODULE_TRACE_FILE"] {
      self.loadedModuleTracePath = try VirtualPath.intern(path: loadedModuleTraceEnvVar)
    } else {
      self.loadedModuleTracePath = try Self.computeSupplementaryOutputPath(
        &parsedOptions, type: .moduleTrace, isOutputOptions: [.emitLoadedModuleTrace],
        outputPath: .emitLoadedModuleTracePath,
        compilerOutputType: compilerOutputType,
        compilerMode: compilerMode,
        emitModuleSeparately: emitModuleSeparately,
        outputFileMap: self.outputFileMap,
        moduleName: moduleOutputInfo.name)
    }

    self.tbdPath = try Self.computeSupplementaryOutputPath(
        &parsedOptions, type: .tbd, isOutputOptions: [.emitTbd],
        outputPath: .emitTbdPath,
        compilerOutputType: compilerOutputType,
        compilerMode: compilerMode,
        emitModuleSeparately: emitModuleSeparately,
        outputFileMap: self.outputFileMap,
        moduleName: moduleOutputInfo.name)
    self.moduleDocOutputPath = try Self.computeModuleDocOutputPath(
        &parsedOptions, moduleOutputPath: self.moduleOutputInfo.output?.outputPath,
        compilerOutputType: compilerOutputType,
        compilerMode: compilerMode,
        outputFileMap: self.outputFileMap,
        moduleName: moduleOutputInfo.name)

    let projectDirectory = Self.computeProjectDirectoryPath(
      moduleOutputPath: self.moduleOutputInfo.output?.outputPath,
      fileSystem: self.fileSystem)
    self.moduleSourceInfoPath = try Self.computeModuleSourceInfoOutputPath(
        &parsedOptions,
        moduleOutputPath: self.moduleOutputInfo.output?.outputPath,
        compilerOutputType: compilerOutputType,
        compilerMode: compilerMode,
        outputFileMap: self.outputFileMap,
        moduleName: moduleOutputInfo.name,
        projectDirectory: projectDirectory)
    self.digesterBaselinePath = try Self.computeDigesterBaselineOutputPath(
      &parsedOptions,
      moduleOutputPath: self.moduleOutputInfo.output?.outputPath,
      mode: self.digesterMode,
      compilerOutputType: compilerOutputType,
      compilerMode: compilerMode,
      outputFileMap: self.outputFileMap,
      moduleName: moduleOutputInfo.name,
      projectDirectory: projectDirectory)
    self.swiftInterfacePath = try Self.computeSupplementaryOutputPath(
        &parsedOptions, type: .swiftInterface, isOutputOptions: [.emitModuleInterface],
        outputPath: .emitModuleInterfacePath,
        compilerOutputType: compilerOutputType,
        compilerMode: compilerMode,
        emitModuleSeparately: emitModuleSeparately,
        outputFileMap: self.outputFileMap,
        moduleName: moduleOutputInfo.name)
    let givenPrivateInterfacePath = try Self.computeSupplementaryOutputPath(
        &parsedOptions, type: .privateSwiftInterface, isOutputOptions: [],
        outputPath: .emitPrivateModuleInterfacePath,
        compilerOutputType: compilerOutputType,
        compilerMode: compilerMode,
        emitModuleSeparately: emitModuleSeparately,
        outputFileMap: self.outputFileMap,
        moduleName: moduleOutputInfo.name)
    let givenPackageInterfacePath = try Self.computeSupplementaryOutputPath(
        &parsedOptions, type: .packageSwiftInterface, isOutputOptions: [],
        outputPath: .emitPackageModuleInterfacePath,
        compilerOutputType: compilerOutputType,
        compilerMode: compilerMode,
        emitModuleSeparately: emitModuleSeparately,
        outputFileMap: self.outputFileMap,
        moduleName: moduleOutputInfo.name)

    // Always emitting private swift interfaces if public interfaces are emitted.'
    // With the introduction of features like @_spi_available, we may print public
    // and private interfaces differently even from the same codebase. For this reason,
    // we should always print private interfaces so that we don’t mix the public interfaces
    // with private Clang modules.
    if let swiftInterfacePath = self.swiftInterfacePath,
        givenPrivateInterfacePath == nil {
      self.swiftPrivateInterfacePath = try VirtualPath.lookup(swiftInterfacePath)
        .replacingExtension(with: .privateSwiftInterface).intern()
    } else {
      self.swiftPrivateInterfacePath = givenPrivateInterfacePath
    }

    if let packageNameInput = parsedOptions.getLastArgument(Option.packageName),
        !packageNameInput.asSingle.isEmpty {
      // Generate a package interface if built with `-package-name` required for decls
      // with the `package` access level. The .package.swiftinterface contains package
      // decls as well as SPI and public decls (superset of a private interface).
      if let publicInterfacePath = self.swiftInterfacePath,
         givenPackageInterfacePath == nil {
        self.swiftPackageInterfacePath = try VirtualPath.lookup(publicInterfacePath)
          .replacingExtension(with: .packageSwiftInterface).intern()
      } else {
        self.swiftPackageInterfacePath = givenPackageInterfacePath
      }
    } else {
      self.swiftPackageInterfacePath = nil
    }

    var optimizationRecordFileType = FileType.yamlOptimizationRecord
    if let argument = parsedOptions.getLastArgument(.saveOptimizationRecordEQ)?.asSingle {
      switch argument {
      case "yaml":
        optimizationRecordFileType = .yamlOptimizationRecord
      case "bitstream":
        optimizationRecordFileType = .bitstreamOptimizationRecord
      default:
        // Don't report an error here, it will be emitted by the frontend.
        break
      }
    }
    self.optimizationRecordFileType = optimizationRecordFileType
    self.optimizationRecordPath = try Self.computeSupplementaryOutputPath(
        &parsedOptions, type: optimizationRecordFileType,
        isOutputOptions: [.saveOptimizationRecord, .saveOptimizationRecordEQ],
        outputPath: .saveOptimizationRecordPath,
        compilerOutputType: compilerOutputType,
        compilerMode: compilerMode,
        emitModuleSeparately: emitModuleSeparately,
        outputFileMap: self.outputFileMap,
        moduleName: moduleOutputInfo.name)

    var apiDescriptorDirectory: VirtualPath? = nil
    if let apiDescriptorDirectoryEnvVar = env["TAPI_SDKDB_OUTPUT_PATH"] {
        apiDescriptorDirectory = try VirtualPath(path: apiDescriptorDirectoryEnvVar)
    } else if let ldTraceFileEnvVar = env["LD_TRACE_FILE"] {
        apiDescriptorDirectory = try VirtualPath(path: ldTraceFileEnvVar).parentDirectory.appending(component: "SDKDB")
    }
    if let apiDescriptorDirectory = apiDescriptorDirectory {
        self.apiDescriptorFilePath = apiDescriptorDirectory
          .appending(component: "\(moduleOutputInfo.name).\(frontendTargetInfo.target.moduleTriple.triple).swift.sdkdb")
          .intern()
    } else {
        self.apiDescriptorFilePath = try Self.computeSupplementaryOutputPath(
            &parsedOptions, type: .jsonAPIDescriptor, isOutputOptions: [],
            outputPath: .emitApiDescriptorPath,
            compilerOutputType: compilerOutputType,
            compilerMode: compilerMode,
            emitModuleSeparately: emitModuleSeparately,
            outputFileMap: self.outputFileMap,
            moduleName: moduleOutputInfo.name)
    }

    Self.validateDigesterArgs(&parsedOptions,
                              moduleOutputInfo: moduleOutputInfo,
                              digesterMode: self.digesterMode,
                              swiftInterfacePath: self.swiftInterfacePath,
                              diagnosticEngine: diagnosticsEngine)

    try verifyOutputOptions()
  }

  public mutating func planBuild() throws -> [Job] {
    let (jobs, incrementalCompilationState) = try planPossiblyIncrementalBuild()
    self.incrementalCompilationState = incrementalCompilationState
    return jobs
  }
}

extension Driver {

  public enum InvocationRunMode: Equatable {
    case normal(isRepl: Bool)
    case subcommand(String)
  }

  /// Determines whether the given arguments constitute a normal invocation,
  /// or whether they invoke a subcommand.
  ///
  /// - Returns: the invocation mode along with the arguments modified for that mode.
  public static func invocationRunMode(
    forArgs args: [String]
  ) throws -> (mode: InvocationRunMode, args: [String]) {

    assert(!args.isEmpty)

    let execName = try VirtualPath(path: args[0]).basenameWithoutExt

    // If we are not run as 'swift' or 'swiftc' or there are no program arguments, always invoke as normal.
    guard ["swift", "swiftc", executableName("swift"), executableName("swiftc")].contains(execName), args.count > 1 else {
      return (.normal(isRepl: false), args)
    }

    // Otherwise, we have a program argument.
    let firstArg = args[1]
    var updatedArgs = args

    // Check for flags associated with frontend tools.
    if firstArg == "-frontend" {
      updatedArgs.replaceSubrange(0...1, with: [executableName("swift-frontend")])
      return (.subcommand(executableName("swift-frontend")), updatedArgs)
    }

    if firstArg == "-modulewrap" {
      updatedArgs[0] = executableName("swift-frontend")
      return (.subcommand(executableName("swift-frontend")), updatedArgs)
    }

    // Only 'swift' supports subcommands.
    guard ["swift", executableName("swift")].contains(execName) else {
      return (.normal(isRepl: false), args)
    }

    // If it looks like an option or a path, then invoke in interactive mode with the arguments as given.
    if firstArg.hasPrefix("-") || firstArg.hasPrefix("/") || firstArg.contains(".") {
        return (.normal(isRepl: false), args)
    }

    // Otherwise, we should have some sort of subcommand.
    // If it is the "built-in" 'repl', then use the normal driver.
    if firstArg == "repl" {
        updatedArgs.remove(at: 1)
        updatedArgs.append("-repl")
        return (.normal(isRepl: true), updatedArgs)
    }

    let subcommand = executableName("swift-\(firstArg)")

    updatedArgs.replaceSubrange(0...1, with: [subcommand])

    return (.subcommand(subcommand), updatedArgs)
  }
}

extension Driver {
  private static func ltoKind(_ parsedOptions: inout ParsedOptions,
                              diagnosticsEngine: DiagnosticsEngine) -> LTOKind? {
    guard let arg = parsedOptions.getLastArgument(.lto)?.asSingle else { return nil }
    guard let kind = LTOKind(rawValue: arg) else {
      diagnosticsEngine.emit(.error_invalid_arg_value_with_allowed(
        arg: .lto, value: arg, options: LTOKind.allCases.map { $0.rawValue }))
      return nil
    }
    return kind
  }
}

extension Driver {
  // Detect mis-use of multi-threading and output file options
  private func verifyOutputOptions() throws {
    if compilerOutputType != .swiftModule,
       parsedOptions.hasArgument(.o),
       linkerOutputType == nil {
      let shouldComplain: Bool
      if numThreads > 0 {
        // Multi-threading compilation has multiple outputs unless there's only
        // one input.
        shouldComplain = self.inputFiles.count > 1
      } else {
        // Single-threaded compilation is a problem if we're compiling more than
        // one file.
        shouldComplain = self.inputFiles.filter { $0.type.isPartOfSwiftCompilation }.count > 1 && .singleCompile != compilerMode
      }
      if shouldComplain {
        diagnosticEngine.emit(.error(Error.cannotSpecify_OForMultipleOutputs),
                              location: nil)
      }
    }
  }
}

// MARK: - Response files.
extension Driver {
  /// Tracks visited response files by unique file ID to prevent recursion,
  /// even if they are referenced with different path strings.
  private struct VisitedResponseFile: Hashable, Equatable {
    var device: UInt64
    var inode: UInt64

    init(fileInfo: FileInfo) {
      self.device = fileInfo.device
      self.inode = fileInfo.inode
    }
  }

  /// Tokenize a single line in a response file.
  ///
  /// This method supports response files with:
  /// 1. Double slash comments at the beginning of a line.
  /// 2. Backslash escaping.
  /// 3. Shell Quoting
  ///
  /// - Returns: An array of 0 or more command line arguments
  ///
  /// - Complexity: O(*n*), where *n* is the length of the line.
  private static func tokenizeResponseFileLine<S: StringProtocol>(_ line: S) -> [String] {
    // Support double dash comments only if they start at the beginning of a line.
    if line.hasPrefix("//") { return [] }

    var tokens: [String] = []
    var token: String = ""
    // Conservatively assume ~1 token per line.
    token.reserveCapacity(line.count)
    // Indicates if we just parsed an escaping backslash.
    var isEscaping = false
    // Indicates if we are currently parsing quoted text.
    var quoted = false

    for char in line {
      // Backslash escapes to the next character.
      if char == #"\"#, !isEscaping {
        isEscaping = true
        continue
      } else if isEscaping {
        // Disable escaping and keep parsing.
        isEscaping = false
      } else if char.isShellQuote {
        // If an unescaped shell quote appears, begin or end quoting.
        quoted.toggle()
        continue
      } else if char.isWhitespace && !quoted {
        // This is unquoted, unescaped whitespace, start a new token.
        if !token.isEmpty {
          tokens.append(token)
          token = ""
        }
        continue
      }

      token.append(char)
    }
    // Add the final token
    if !token.isEmpty {
      tokens.append(token)
    }

    return tokens
  }

  // https://docs.microsoft.com/en-us/previous-versions//17w5ykft(v=vs.85)?redirectedfrom=MSDN
  private static func tokenizeWindowsResponseFile(_ content: String) -> [String] {
    let whitespace: [Character] = [" ", "\t", "\r", "\n", "\0" ]

    var content = content
    var tokens: [String] = []
    var token: String = ""
    var quoted: Bool = false

    while !content.isEmpty {
      // Eat whitespace at the beginning
      if token.isEmpty {
        if let end = content.firstIndex(where: { !whitespace.contains($0) }) {
          let count = content.distance(from: content.startIndex, to: end)
          content.removeFirst(count)
        }

        // Stop if this was trailing whitespace.
        if content.isEmpty { break }
      }

      // Treat whitespace, double quotes, and backslashes as special characters.
      if let next = content.firstIndex(where: { (quoted ? ["\\", "\""] : [" ", "\t", "\r", "\n", "\0", "\\", "\""]).contains($0) }) {
        let count = content.distance(from: content.startIndex, to: next)
        token.append(contentsOf: content[..<next])
        content.removeFirst(count)

        switch content.first {
        case " ", "\t", "\r", "\n", "\0":
          tokens.append(token)
          token = ""
          content.removeFirst(1)

        case "\\":
          // Backslashes are interpreted in a special manner due to use as both
          // a path separator and an escape character.  Consume runs of
          // backslashes and following double quote if escaped.
          //
          //  - If an even number of backslashes is followed by a double quote,
          //  one backslash is emitted for each pair, and the last double quote
          //  remains unconsumed.  The quote will be processed as the start or
          //  end of a quoted string by the tokenizer.
          //
          //  - If an odd number of backslashes is followed by a double quote,
          //  one backslash is emitted for each pair, and a double quote is
          //  emitted for the trailing backslash and quote pair.  The double
          //  quote is consumed.
          //
          //  - Otherwise, backslashes are treated literally.
          if let next = content.firstIndex(where: { $0 != "\\" }) {
            let count = content.distance(from: content.startIndex, to: next)
            if content[next] == "\"" {
              token.append(String(repeating: "\\", count: count / 2))
              content.removeFirst(count)

              if count % 2 != 0 {
                token.append("\"")
                content.removeFirst(1)
              }
            } else {
              token.append(String(repeating: "\\", count: count))
              content.removeFirst(count)
            }
          } else {
            token.append(String(repeating: "\\", count: content.count))
            content.removeFirst(content.count)
          }

        case "\"":
          content.removeFirst(1)

          if quoted, content.first == "\"" {
            // Consecutive double quotes inside a quoted string implies one quote
            token.append("\"")
            content.removeFirst(1)
          }

          quoted.toggle()

        default:
          fatalError("unexpected character '\(content.first!)'")
        }
      } else {
        // Consume to end of content.
        token.append(content)
        content.removeFirst(content.count)
        break
      }
    }

    if !token.isEmpty { tokens.append(token) }
    return tokens.filter { !$0.isEmpty }
  }

  /// Tokenize each line of the response file, omitting empty lines.
  ///
  /// - Parameter content: response file's content to be tokenized.
  private static func tokenizeResponseFile(_ content: String) -> [String] {
    #if !canImport(Darwin) && !os(Linux) && !os(Android) && !os(OpenBSD) && !os(Windows)
      #warning("Response file tokenization unimplemented for platform; behavior may be incorrect")
    #endif
#if os(Windows)
    return content.split { $0 == "\n" || $0 == "\r\n" }
                  .flatMap { tokenizeWindowsResponseFile(String($0)) }
#else
    return content.split { $0 == "\n" || $0 == "\r\n" }
                  .flatMap { tokenizeResponseFileLine($0) }
#endif
  }

  /// Resolves the absolute path for a response file.
  ///
  /// A response file may be specified using either an absolute or relative
  /// path. Relative paths resolved relative to the given base directory, which
  /// defaults to the process's current working directory, or are forbidden if
  /// the base path is nil.
  ///
  /// - Parameter path: An absolute or relative path to a response file.
  /// - Parameter basePath: An absolute path used to resolve relative paths; if
  ///   nil, relative paths will not be allowed.
  /// - Returns: The absolute path to the response file if it was a valid file,
  ///   or nil if it was not a file or was a relative path when `basePath` was
  ///   nil.
  private static func resolveResponseFile(
    _ path: String,
    relativeTo basePath: AbsolutePath?,
    fileSystem: FileSystem
  ) -> AbsolutePath? {
    let responseFile: AbsolutePath
    if let basePath = basePath {
      guard let absolutePath = try? AbsolutePath(validating: path, relativeTo: basePath) else {
          return nil
      }
      responseFile = absolutePath
    } else {
      guard let absolutePath = try? AbsolutePath(validating: path) else {
        return nil
      }
      responseFile = absolutePath
    }
    return fileSystem.isFile(responseFile) ? responseFile : nil
  }

  /// Tracks the given response file and returns a token if it has not already
  /// been visited.
  ///
  /// - Returns: A value that uniquely identifies the response file that was
  ///   added to `visitedResponseFiles` and should be removed when the caller
  ///   is done visiting the file, or nil if visiting the file would result in
  ///   recursion.
  private static func shouldVisitResponseFile(
    _ path: AbsolutePath,
    fileSystem: FileSystem,
    visitedResponseFiles: inout Set<VisitedResponseFile>
  ) throws -> VisitedResponseFile? {
    let visitationToken = try VisitedResponseFile(fileInfo: fileSystem.getFileInfo(path))
    return visitedResponseFiles.insert(visitationToken).inserted ? visitationToken : nil
  }

  /// Recursively expands the response files.
  /// - Parameter basePath: The absolute path used to resolve response files
  ///   with relative path names. If nil, relative paths will be ignored.
  /// - Parameter visitedResponseFiles: Set containing visited response files
  ///   to detect recursive parsing.
  private static func expandResponseFiles(
    _ args: [String],
    fileSystem: FileSystem,
    diagnosticsEngine: DiagnosticsEngine,
    relativeTo basePath: AbsolutePath?,
    visitedResponseFiles: inout Set<VisitedResponseFile>
  ) throws -> [String] {
    var result: [String] = []

    // Go through each arg and add arguments from response files.
    for arg in args {
      if arg.first == "@", let responseFile = resolveResponseFile(String(arg.dropFirst()), relativeTo: basePath, fileSystem: fileSystem) {
        // Guard against infinite parsing loop.
        guard let visitationToken = try shouldVisitResponseFile(responseFile, fileSystem: fileSystem, visitedResponseFiles: &visitedResponseFiles) else {
          diagnosticsEngine.emit(.warn_recursive_response_file(responseFile))
          continue
        }
        defer {
          visitedResponseFiles.remove(visitationToken)
        }

        let contents = try fileSystem.readFileContents(responseFile).cString
        let lines = tokenizeResponseFile(contents)
        result.append(contentsOf: try expandResponseFiles(lines, fileSystem: fileSystem, diagnosticsEngine: diagnosticsEngine, relativeTo: basePath, visitedResponseFiles: &visitedResponseFiles))
      } else {
        result.append(arg)
      }
    }

    return result
  }

  /// Expand response files in the input arguments and return a new argument list.
  public static func expandResponseFiles(
    _ args: [String],
    fileSystem: FileSystem,
    diagnosticsEngine: DiagnosticsEngine
  ) throws -> [String] {
    var visitedResponseFiles = Set<VisitedResponseFile>()
    return try expandResponseFiles(args, fileSystem: fileSystem, diagnosticsEngine: diagnosticsEngine, relativeTo: fileSystem.currentWorkingDirectory, visitedResponseFiles: &visitedResponseFiles)
  }
}

extension Diagnostic.Message {
  static func warn_unused_option(_ option: ParsedOption) -> Diagnostic.Message {
    .warning("Unused option: \(option)")
  }
}

extension Driver {
  /// Determine the driver kind based on the command-line arguments, consuming the arguments
  /// conveying this information.
  @_spi(Testing) public static func determineDriverKind(
    args: inout [String]
  ) throws -> DriverKind {
    // Get the basename of the driver executable.
    let execRelPath = args.removeFirst()
    var driverName = try VirtualPath(path: execRelPath).basenameWithoutExt

    // Determine if the driver kind is being overridden.
    let driverModeOption = "--driver-mode="
    if let firstArg = args.first, firstArg.hasPrefix(driverModeOption) {
      args.removeFirst()
      driverName = String(firstArg.dropFirst(driverModeOption.count))
    }

    switch driverName {
    case "swift":
      return .interactive
    case "swiftc":
      return .batch
    default:
      throw Error.invalidDriverName(driverName)
    }
  }

  /// Run the driver.
  public mutating func run(
    jobs: [Job]
  ) throws {
    if parsedOptions.hasArgument(.v) {
      try printVersion(outputStream: &stderrStream)
    }

    let forceResponseFiles = parsedOptions.contains(.driverForceResponseFiles)

    // If we're only supposed to print the jobs, do so now.
    if parsedOptions.contains(.driverPrintJobs) {
      for job in jobs {
        print(try executor.description(of: job, forceResponseFiles: forceResponseFiles))
      }
      return
    }

    // If we're only supposed to explain a dependency on a given module, do so now.
    if let explainModuleName = parsedOptions.getLastArgument(.explainModuleDependency) {
      guard let dependencyPlanner = explicitDependencyBuildPlanner else {
        fatalError("Cannot explain dependency without Explicit Build Planner")
      }
      guard let dependencyPaths = try dependencyPlanner.explainDependency(explainModuleName.asSingle) else {
        diagnosticEngine.emit(.remark("No such module dependency found: '\(explainModuleName.asSingle)'"))
        return
      }
      diagnosticEngine.emit(.remark("Module '\(moduleOutputInfo.name)' depends on '\(explainModuleName.asSingle)'"))
      for path in dependencyPaths {
        var pathString:String = ""
        for (index, moduleId) in path.enumerated() {
          switch moduleId {
          case .swift(let moduleName):
            pathString = pathString + "[" + moduleName + "]"
          case .swiftPrebuiltExternal(let moduleName):
            pathString = pathString + "[" + moduleName + "]"
          case .clang(let moduleName):
            pathString = pathString + "[" + moduleName + "](ObjC)"
          case .swiftPlaceholder(_):
            fatalError("Unexpected unresolved Placeholder module")
          }
          if index < path.count - 1 {
            pathString = pathString + " -> "
          }
        }
        diagnosticEngine.emit(.note(pathString))
      }
    }

    if parsedOptions.contains(.driverPrintOutputFileMap) {
      if let outputFileMap = self.outputFileMap {
        stderrStream.send(outputFileMap.description)
        stderrStream.flush()
      } else {
        diagnosticEngine.emit(.error_no_output_file_map_specified)
      }
      return
    }

    if parsedOptions.contains(.driverPrintBindings) {
      for job in jobs {
        printBindings(job)
      }
      return
    }

    if parsedOptions.contains(.driverPrintActions) {
      // Print actions using the same style as the old C++ driver
      // This is mostly for testing purposes. We should print semantically
      // equivalent actions as the old driver.
      printActions(jobs)
      return
    }

    if parsedOptions.contains(.driverPrintGraphviz) {
      var serializer = DOTJobGraphSerializer(jobs: jobs)
      serializer.writeDOT(to: &stdoutStream)
      stdoutStream.flush()
      return
    }

    let toolExecutionDelegate = createToolExecutionDelegate()

    defer {
      // Attempt to cleanup temporary files before exiting, unless -save-temps was passed or a job crashed.
      if !parsedOptions.hasArgument(.saveTemps) && !toolExecutionDelegate.anyJobHadAbnormalExit {
          try? executor.resolver.removeTemporaryDirectory()
      }
    }

    // Jobs which are run as child processes of the driver.
    var childJobs: [Job]
    // A job which runs in-place, replacing the driver.
    var inPlaceJob: Job?

    if jobs.contains(where: { $0.requiresInPlaceExecution }) {
      childJobs = jobs.filter { !$0.requiresInPlaceExecution }
      let inPlaceJobs = jobs.filter(\.requiresInPlaceExecution)
      assert(inPlaceJobs.count == 1,
             "Cannot execute multiple jobs in-place")
      inPlaceJob = inPlaceJobs.first
    } else if jobs.count == 1 && !parsedOptions.hasArgument(.parseableOutput) &&
                buildRecordInfo == nil {
      // Only one job and no cleanup required, e.g. not writing build record
      inPlaceJob = jobs[0]
      childJobs = []
    } else {
      childJobs = jobs
      inPlaceJob = nil
    }
    inPlaceJob?.requiresInPlaceExecution = true

    if !childJobs.isEmpty {
      do {
        defer {
          writeIncrementalBuildInformation(jobs)
        }
        try performTheBuild(allJobs: childJobs,
                            jobExecutionDelegate: toolExecutionDelegate,
                            forceResponseFiles: forceResponseFiles)
      }
    }

    // If we have a job to run in-place, do so at the end.
    if let inPlaceJob = inPlaceJob {
      // Print the driver source version first before we print the compiler
      // versions.
      if inPlaceJob.kind == .versionRequest && !Driver.driverSourceVersion.isEmpty {
        stderrStream.send("swift-driver version: \(Driver.driverSourceVersion) ")
        if let blocklistVersion = try Driver.findCompilerClientsConfigVersion(RelativeTo: try toolchain.executableDir) {
          stderrStream.send("\(blocklistVersion) ")
        }
        stderrStream.flush()
      }
      // In verbose mode, print out the job
      if parsedOptions.contains(.v) {
        let arguments: [String] = try executor.resolver.resolveArgumentList(for: inPlaceJob,
                                                                            useResponseFiles: forceResponseFiles ? .forced : .heuristic)
        stdoutStream.send("\(arguments.map { $0.spm_shellEscaped() }.joined(separator: " "))\n")
        stdoutStream.flush()
      }
      try executor.execute(job: inPlaceJob,
                           forceResponseFiles: forceResponseFiles,
                           recordedInputModificationDates: recordedInputModificationDates)
    }

    // If requested, warn for options that weren't used by the driver after the build is finished.
    if parsedOptions.hasArgument(.driverWarnUnusedOptions) {
      for option in parsedOptions.unconsumedOptions {
        diagnosticEngine.emit(.warn_unused_option(option))
      }
    }
  }

  mutating func createToolExecutionDelegate() -> ToolExecutionDelegate {
    var mode: ToolExecutionDelegate.Mode = .regular

    // FIXME: Old driver does _something_ if both -parseable-output and -v are passed.
    // Not sure if we want to support that.
    if parsedOptions.contains(.parseableOutput) {
      mode = .parsableOutput
    } else if parsedOptions.contains(.v) {
      mode = .verbose
    } else if integratedDriver {
      mode = .silent
    }

    return ToolExecutionDelegate(
      mode: mode,
      buildRecordInfo: buildRecordInfo,
      showJobLifecycle: showJobLifecycle,
      argsResolver: executor.resolver,
      diagnosticEngine: diagnosticEngine)
  }

  private mutating func performTheBuild(
    allJobs: [Job],
    jobExecutionDelegate: JobExecutionDelegate,
    forceResponseFiles: Bool
  ) throws {
    let continueBuildingAfterErrors = computeContinueBuildingAfterErrors()
    try executor.execute(
      workload: .init(allJobs,
                      incrementalCompilationState,
                      interModuleDependencyGraph,
                      continueBuildingAfterErrors: continueBuildingAfterErrors),
      delegate: jobExecutionDelegate,
      numParallelJobs: numParallelJobs ?? 1,
      forceResponseFiles: forceResponseFiles,
      recordedInputModificationDates: recordedInputModificationDates)
  }

  public func writeIncrementalBuildInformation(_ jobs: [Job]) {
    // In case the write fails, don't crash the build.
    // A mitigation to rdar://76359678.
    // If the write fails, import incrementality is lost, but it is not a fatal error.
    guard
      let buildRecordInfo = self.buildRecordInfo,
      let absPath = buildRecordInfo.buildRecordPath.absolutePath
    else {
      return
    }

    let buildRecord = buildRecordInfo.buildRecord(
      jobs, self.incrementalCompilationState?.blockingConcurrentMutationToProtectedState{
        $0.skippedCompilationInputs
      })

    if
      let incrementalCompilationState = self.incrementalCompilationState,
      incrementalCompilationState.info.isCrossModuleIncrementalBuildEnabled
    {
      do {
        try incrementalCompilationState.writeDependencyGraph(to: buildRecordInfo.dependencyGraphPath, buildRecord)
      } catch {
        diagnosticEngine.emit(
          .warning("next compile won't be incremental; could not write dependency graph: \(error.localizedDescription)"))
        /// Ensure that a bogus dependency graph is not used next time.
        buildRecordInfo.removeBuildRecord()
        buildRecordInfo.removeInterModuleDependencyGraph()
        return
      }
      do {
        try incrementalCompilationState.writeInterModuleDependencyGraph(buildRecordInfo)
      } catch {
        diagnosticEngine.emit(
          .warning("next compile must run a full dependency scan; could not write inter-module dependency graph: \(error.localizedDescription)"))
        buildRecordInfo.removeBuildRecord()
        buildRecordInfo.removeInterModuleDependencyGraph()
        return
      }
    } else {
      // FIXME: This is all legacy code. Once the cross module incremental build
      // becomes the default:
      //
      // 1) Delete this branch
      // 2) Delete the parts of the incremental build that talk about anything
      //    derived from `buildRecordPath`
      // 3) Delete the Yams dependency.

      // Before writing to the dependencies file path, preserve any previous file
      // that may have been there. No error handling -- this is just a nicety, it
      // doesn't matter if it fails.
      // Added for the sake of compatibility with the legacy driver.
      try? fileSystem.move(
        from: absPath, to: absPath.appending(component: absPath.basename + "~"))

      guard let contents = buildRecord.encode(diagnosticEngine: diagnosticEngine) else {
        diagnosticEngine.emit(.warning_could_not_write_build_record(absPath))
        return
      }

      do {
        try fileSystem.writeFileContents(absPath,
                                         bytes: ByteString(encodingAsUTF8: contents))
      } catch {
        diagnosticEngine.emit(.warning_could_not_write_build_record(absPath))
      }
    }
  }

  private func printBindings(_ job: Job) {
    stdoutStream.send(#"# ""#).send(targetTriple.triple)
    stdoutStream.send(#"" - ""#).send(job.tool.basename)
    stdoutStream.send(#"", inputs: ["#)
    stdoutStream.send(job.displayInputs.map { "\"" + $0.file.name + "\"" }.joined(separator: ", "))

    stdoutStream.send("], output: {")

    stdoutStream.send(job.outputs.map { $0.type.name + ": \"" + $0.file.name + "\"" }.joined(separator: ", "))

    stdoutStream.send("}\n")
    stdoutStream.flush()
  }

  /// This handles -driver-print-actions flag. The C++ driver has a concept of actions
  /// which it builds up a list of actions before then creating them into jobs.
  /// The swift-driver doesn't have actions, so the logic here takes the jobs and tries
  /// to mimic the actions that would be created by the C++ driver and
  /// prints them in *hopefully* the same order.
  private mutating func printActions(_ jobs: [Job]) {
    defer {
      stdoutStream.flush()
    }

    // Put bridging header as first input if we have it
    let allInputs: [TypedVirtualPath]
    if let objcHeader = importedObjCHeader, bridgingPrecompiledHeader != nil {
      allInputs = [TypedVirtualPath(file: objcHeader, type: .objcHeader)] + inputFiles
    } else {
      allInputs = inputFiles
    }

    var jobIdMap = Dictionary<Job, UInt>()
    // The C++ driver treats each input as an action, we should print them as
    // an action too for testing purposes.
    var inputIdMap = Dictionary<TypedVirtualPath, UInt>()
    var nextId: UInt = 0
    var allInputsIterator = allInputs.makeIterator()
    for job in jobs {
      // After "module input" jobs, print any left over inputs
      switch job.kind {
      case .generatePCH, .compile, .backend:
        break
      default:
        while let input = allInputsIterator.next() {
          Self.printInputIfNew(input, inputIdMap: &inputIdMap, nextId: &nextId)
        }
      }
      // All input action IDs for this action.
      var inputIds = [UInt]()

      var jobInputs = job.primaryInputs.isEmpty ? job.inputs : job.primaryInputs
      if let pchPath = bridgingPrecompiledHeader, job.kind == .compile {
        jobInputs.append(TypedVirtualPath(file: pchPath, type: .pch))
      }
      // Collect input job IDs.
      for input in jobInputs {
        if let id = inputIdMap[input] {
          inputIds.append(id)
          continue
        }
        var foundInput = false
        for (prevJob, id) in jobIdMap {
          if prevJob.outputs.contains(input) {
            foundInput = true
            inputIds.append(id)
            break
          }
        }
        if !foundInput {
          while let nextInputAction = allInputsIterator.next() {
            Self.printInputIfNew(nextInputAction, inputIdMap: &inputIdMap, nextId: &nextId)
            if let id = inputIdMap[input] {
              inputIds.append(id)
              break
            }
          }
        }
      }

      // Print current Job
      stdoutStream.send("\(nextId): ").send(job.kind.rawValue).send(", {")
      switch job.kind {
      // Don't sort for compile jobs. Puts pch last
      case .compile:
        stdoutStream.send(inputIds.map(\.description).joined(separator: ", "))
      default:
        stdoutStream.send(inputIds.sorted().map(\.description).joined(separator: ", "))
      }
      var typeName = job.outputs.first?.type.name
      if typeName == nil {
        typeName = "none"
      }
      stdoutStream.send("}, \(typeName!)\n")
      jobIdMap[job] = nextId
      nextId += 1
    }
  }

  private static func printInputIfNew(_ input: TypedVirtualPath, inputIdMap: inout [TypedVirtualPath: UInt], nextId: inout UInt) {
    if inputIdMap[input] == nil {
      stdoutStream.send("\(nextId): input, ")
      stdoutStream.send("\"\(input.file)\", \(input.type)\n")
      inputIdMap[input] = nextId
      nextId += 1
    }
  }

  private func printVersion<S: OutputByteStream>(outputStream: inout S) throws {
    outputStream.send("\(frontendTargetInfo.compilerVersion)\n")
    outputStream.send("Target: \(frontendTargetInfo.target.triple.triple)\n")
    outputStream.flush()
  }
}

extension Diagnostic.Message {
  static func warn_recursive_response_file(_ path: AbsolutePath) -> Diagnostic.Message {
    .warning("response file '\(path)' is recursively expanded")
  }

  static var error_no_swift_frontend: Diagnostic.Message {
    .error("-driver-use-frontend-path requires a Swift compiler executable argument")
  }

  static var warning_cannot_multithread_batch_mode: Diagnostic.Message {
    .warning("ignoring -num-threads argument; cannot multithread batch mode")
  }

  static var error_no_output_file_map_specified: Diagnostic.Message {
    .error("no output file map specified")
  }
}

extension Driver {
  /// Parse an option's value into an `Int`.
  ///
  /// If the parsed options don't contain an option with this value, returns
  /// `nil`.
  /// If the parsed option does contain an option with this value, but the
  /// value is not parsable as an `Int`, emits an error and returns `nil`.
  /// Otherwise, returns the parsed value.
  private static func parseIntOption(
    _ parsedOptions: inout ParsedOptions,
    option: Option,
    diagnosticsEngine: DiagnosticsEngine
  ) -> Int? {
    guard let argument = parsedOptions.getLastArgument(option) else {
      return nil
    }

    guard let value = Int(argument.asSingle) else {
      diagnosticsEngine.emit(.error_invalid_arg_value(arg: option, value: argument.asSingle))
      return nil
    }

    return value
  }
}

extension Driver {
  private static func computeFileListThreshold(
    _ parsedOptions: inout ParsedOptions,
    diagnosticsEngine: DiagnosticsEngine
  ) throws -> Int {
    let hasUseFileLists = parsedOptions.hasArgument(.driverUseFilelists)

    if hasUseFileLists {
      diagnosticsEngine.emit(.warn_use_filelists_deprecated)
    }

    if let threshold = parsedOptions.getLastArgument(.driverFilelistThreshold)?.asSingle {
      if let thresholdInt = Int(threshold) {
        return thresholdInt
      } else {
        throw Error.invalidArgumentValue(Option.driverFilelistThreshold.spelling, threshold)
      }
    } else if hasUseFileLists {
      return 0
    }

    return 128
  }
}

private extension Diagnostic.Message {
  static var warn_use_filelists_deprecated: Diagnostic.Message {
    .warning("the option '-driver-use-filelists' is deprecated; use '-driver-filelist-threshold=0' instead")
  }
}

extension Driver {
  /// Compute the compiler mode based on the options.
  private static func computeCompilerMode(
    _ parsedOptions: inout ParsedOptions,
    driverKind: DriverKind,
    diagnosticsEngine: DiagnosticsEngine
  ) throws -> CompilerMode {
    // Some output flags affect the compiler mode.
    if let outputOption = parsedOptions.getLast(in: .modes) {
      switch outputOption.option {
      case .emitImportedModules:
        return .singleCompile
      case .repl, .lldbRepl:
        return .repl

      case .deprecatedIntegratedRepl:
        throw Error.integratedReplRemoved

      case .emitPcm:
        return .compilePCM

      case .dumpPcm:
        return .dumpPCM

      default:
        // Output flag doesn't determine the compiler mode.
        break
      }
    }

    if driverKind == .interactive {
      if parsedOptions.hasAnyInput {
        return .immediate
      } else {
        if parsedOptions.contains(Option.repl) {
          return .repl
        } else {
          return .intro
        }
      }
    }

    let useWMO = parsedOptions.hasFlag(positive: .wholeModuleOptimization, negative: .noWholeModuleOptimization, default: false)
    let hasIndexFile = parsedOptions.hasArgument(.indexFile)
    let wantBatchMode = parsedOptions.hasFlag(positive: .enableBatchMode, negative: .disableBatchMode, default: false)

    // AST dump doesn't work with `-wmo`/`-index-file`. Since it's not common to want to dump
    // the AST, we assume that's the priority and ignore those flags, but we warn the
    // user about this decision.
    if useWMO && parsedOptions.hasArgument(.dumpAst) {
      diagnosticsEngine.emit(.warning_option_overrides_another(overridingOption: .dumpAst,
                                                               overridenOption: .wmo))
      parsedOptions.eraseArgument(.wmo)
      return .standardCompile
    }

    if hasIndexFile && parsedOptions.hasArgument(.dumpAst) {
      diagnosticsEngine.emit(.warning_option_overrides_another(overridingOption: .dumpAst,
                                                               overridenOption: .indexFile))
      parsedOptions.eraseArgument(.indexFile)
      parsedOptions.eraseArgument(.indexFilePath)
      parsedOptions.eraseArgument(.indexStorePath)
      parsedOptions.eraseArgument(.indexIgnoreSystemModules)
      return .standardCompile
    }

    if useWMO || hasIndexFile {
      if wantBatchMode {
        let disablingOption: Option = useWMO ? .wholeModuleOptimization : .indexFile
        diagnosticsEngine.emit(.warn_ignoring_batch_mode(disablingOption))
      }

      return .singleCompile
    }

    // For batch mode, collect information
    if wantBatchMode {
      let batchSeed = parseIntOption(&parsedOptions, option: .driverBatchSeed, diagnosticsEngine: diagnosticsEngine)
      let batchCount = parseIntOption(&parsedOptions, option: .driverBatchCount, diagnosticsEngine: diagnosticsEngine)
      let batchSizeLimit = parseIntOption(&parsedOptions, option: .driverBatchSizeLimit, diagnosticsEngine: diagnosticsEngine)
      return .batchCompile(BatchModeInfo(seed: batchSeed, count: batchCount, sizeLimit: batchSizeLimit))
    }

    return .standardCompile
  }
}

extension Diagnostic.Message {
  static func warn_ignoring_batch_mode(_ option: Option) -> Diagnostic.Message {
    .warning("ignoring '-enable-batch-mode' because '\(option.spelling)' was also specified")
  }
}

/// Input and output file handling.
extension Driver {
  /// Apply the given working directory to all paths in the parsed options.
  private static func applyWorkingDirectory(_ workingDirectory: AbsolutePath,
                                            to parsedOptions: inout ParsedOptions) throws {
    try parsedOptions.forEachModifying { parsedOption in
      // Only translate options whose arguments are paths.
      if !parsedOption.option.attributes.contains(.argumentIsPath) { return }

      let translatedArgument: ParsedOption.Argument
      switch parsedOption.argument {
      case .none:
        return

      case .single(let arg):
        if arg == "-" {
          translatedArgument = parsedOption.argument
        } else {
          translatedArgument = .single(try AbsolutePath(validating: arg, relativeTo: workingDirectory).pathString)
        }

      case .multiple(let args):
        translatedArgument = .multiple(try args.map { arg in
          try AbsolutePath(validating: arg, relativeTo: workingDirectory).pathString
        })
      }

      parsedOption = .init(
        option: parsedOption.option,
        argument: translatedArgument,
        index: parsedOption.index
      )
    }
  }

  /// Collect all of the input files from the parsed options, translating them into input files.
  private static func collectInputFiles(
    _ parsedOptions: inout ParsedOptions,
    diagnosticsEngine: DiagnosticsEngine,
    fileSystem: FileSystem
  ) throws -> [TypedVirtualPath] {
    var swiftFiles = [String: String]() // [Basename: Path]
    var paths: [TypedVirtualPath] = try parsedOptions.allInputs.map { input in
      // Standard input is assumed to be Swift code.
      if input == "-" {
        return TypedVirtualPath(file: .standardInput, type: .swift)
      }

      // Resolve the input file.
      let inputHandle = try VirtualPath.intern(path: input)
      let inputFile = VirtualPath.lookup(inputHandle)
      let fileExtension = inputFile.extension ?? ""

      // Determine the type of the input file based on its extension.
      // If we don't recognize the extension, treat it as an object file.
      // FIXME: The object-file default is carried over from the existing
      // driver, but seems odd.
      let fileType = FileType(rawValue: fileExtension) ?? FileType.object

      if fileType == .swift {
        let basename = inputFile.basename
        if let originalPath = swiftFiles[basename] {
          diagnosticsEngine.emit(.error_two_files_same_name(basename: basename, firstPath: originalPath, secondPath: input))
          diagnosticsEngine.emit(.note_explain_two_files_same_name)
          throw ErrorDiagnostics.emitted
        } else {
          swiftFiles[basename] = input
        }
      }

      return TypedVirtualPath(file: inputHandle, type: fileType)
    }

    if parsedOptions.hasArgument(.e) {
      if let mainPath = swiftFiles["main.swift"] {
        diagnosticsEngine.emit(.error_two_files_same_name(basename: "main.swift", firstPath: mainPath, secondPath: "-e"))
        diagnosticsEngine.emit(.note_explain_two_files_same_name)
        throw ErrorDiagnostics.emitted
      }

      try withTemporaryDirectory(dir: fileSystem.tempDirectory, removeTreeOnDeinit: false) { absPath in
        let filePath = VirtualPath.absolute(absPath.appending(component: "main.swift"))

        try fileSystem.writeFileContents(filePath) { file in
          file.send(###"#sourceLocation(file: "-e", line: 1)\###n"###)
          for option in parsedOptions.arguments(for: .e) {
            file.send("\(option.argument.asSingle)\n")
          }
        }

        paths.append(TypedVirtualPath(file: filePath.intern(), type: .swift))
      }
    }

    return paths
  }

  /// Determine the primary compiler and linker output kinds.
  private static func determinePrimaryOutputs(
    _ parsedOptions: inout ParsedOptions,
    targetTriple: Triple,
    driverKind: DriverKind,
    diagnosticsEngine: DiagnosticsEngine
  ) -> (FileType?, LinkOutputType?) {
    // By default, the driver does not link its output. However, this will be updated below.
    var compilerOutputType: FileType? = (driverKind == .interactive ? nil : .object)
    var linkerOutputType: LinkOutputType? = nil
    let objectLikeFileType: FileType = parsedOptions.getLastArgument(.lto) != nil ? .llvmBitcode : .object

    if let outputOption = parsedOptions.getLast(in: .modes) {
      switch outputOption.option {
      case .emitExecutable:
        if parsedOptions.contains(.static) && !targetTriple.supportsStaticExecutables {
          diagnosticsEngine.emit(.error_static_emit_executable_disallowed)
        }
        linkerOutputType = .executable
        compilerOutputType = objectLikeFileType

      case .emitLibrary:
        linkerOutputType = parsedOptions.hasArgument(.static) ? .staticLibrary : .dynamicLibrary
        compilerOutputType = objectLikeFileType

      case .emitObject, .c:
        compilerOutputType = objectLikeFileType

      case .emitAssembly, .S:
        compilerOutputType = .assembly

      case .emitSil:
        compilerOutputType = .sil

      case .emitSilgen:
        compilerOutputType = .raw_sil

      case .emitSib:
        compilerOutputType = .sib

      case .emitSibgen:
        compilerOutputType = .raw_sib

      case .emitIrgen, .emitIr:
        compilerOutputType = .llvmIR

      case .emitBc:
        compilerOutputType = .llvmBitcode

      case .dumpAst:
        compilerOutputType = .ast

      case .emitPcm:
        compilerOutputType = .pcm

      case .dumpPcm:
        compilerOutputType = nil

      case .emitImportedModules:
        compilerOutputType = .importedModules

      case .indexFile:
        compilerOutputType = .indexData

      case .parse, .resolveImports, .typecheck,
           .dumpParse, .printAst, .dumpTypeRefinementContexts, .dumpScopeMaps,
           .dumpInterfaceHash, .dumpTypeInfo, .verifyDebugInfo:
        compilerOutputType = nil

      case .i:
        diagnosticsEngine.emit(.error_i_mode)

      case .repl, .deprecatedIntegratedRepl, .lldbRepl:
        compilerOutputType = nil

      case .interpret:
        compilerOutputType = nil

      case .scanDependencies:
        compilerOutputType = .jsonDependencies

      default:
        fatalError("unhandled output mode option \(outputOption)")
      }
    } else if parsedOptions.hasArgument(.emitModule, .emitModulePath) {
      compilerOutputType = .swiftModule
    } else if driverKind != .interactive {
      compilerOutputType = objectLikeFileType
      linkerOutputType = .executable
    }

    // warn if -embed-bitcode is set and the output type is not an object
    if parsedOptions.hasArgument(.embedBitcode) && compilerOutputType != .object {
      diagnosticsEngine.emit(.warn_ignore_embed_bitcode)
      parsedOptions.eraseArgument(.embedBitcode)
    }
    if parsedOptions.hasArgument(.embedBitcodeMarker) && compilerOutputType != .object {
      diagnosticsEngine.emit(.warn_ignore_embed_bitcode_marker)
      parsedOptions.eraseArgument(.embedBitcodeMarker)
    }

    return (compilerOutputType, linkerOutputType)
  }
}

extension Diagnostic.Message {
  static var error_i_mode: Diagnostic.Message {
    .error(
      """
      the flag '-i' is no longer required and has been removed; \
      use '\(DriverKind.interactive.usage) input-filename'
      """
    )
  }

  static var warn_ignore_embed_bitcode: Diagnostic.Message {
    .warning("ignoring -embed-bitcode since no object file is being generated")
  }

  static var warn_ignore_embed_bitcode_marker: Diagnostic.Message {
    .warning("ignoring -embed-bitcode-marker since no object file is being generated")
  }

  static func error_two_files_same_name(basename: String, firstPath: String, secondPath: String) -> Diagnostic.Message {
    .error("filename \"\(basename)\" used twice: '\(firstPath)' and '\(secondPath)'")
  }

  static var note_explain_two_files_same_name: Diagnostic.Message {
    .note("filenames are used to distinguish private declarations with the same name")
  }
}

// Multithreading
extension Driver {
  /// Determine the number of threads to use for a multithreaded build,
  /// or zero to indicate a single-threaded build.
  static func determineNumThreads(
    _ parsedOptions: inout ParsedOptions,
    compilerMode: CompilerMode, diagnosticsEngine: DiagnosticsEngine
  ) -> Int {
    guard let numThreadsArg = parsedOptions.getLastArgument(.numThreads) else {
      return 0
    }

    // Make sure we have a non-negative integer value.
    guard let numThreads = Int(numThreadsArg.asSingle), numThreads >= 0 else {
      diagnosticsEngine.emit(.error_invalid_arg_value(arg: .numThreads, value: numThreadsArg.asSingle))
      return 0
    }

    if case .batchCompile = compilerMode {
      diagnosticsEngine.emit(.warning_cannot_multithread_batch_mode)
      return 0
    }

    return numThreads
  }

  /// Determine the number of parallel jobs to execute.
  static func determineNumParallelJobs(
    _ parsedOptions: inout ParsedOptions,
    diagnosticsEngine: DiagnosticsEngine,
    env: [String: String]
  ) -> Int? {
    guard let numJobs = parseIntOption(&parsedOptions, option: .j, diagnosticsEngine: diagnosticsEngine) else {
      return nil
    }

    guard numJobs >= 1 else {
      diagnosticsEngine.emit(.error_invalid_arg_value(arg: .j, value: String(numJobs)))
      return nil
    }

    if let determinismRequested = env["SWIFTC_MAXIMUM_DETERMINISM"], !determinismRequested.isEmpty {
      diagnosticsEngine.emit(.remark_max_determinism_overriding(.j))
      return 1
    }

    return numJobs
  }

  private mutating func computeContinueBuildingAfterErrors() -> Bool {
    // Note: Batch mode handling of serialized diagnostics requires that all
    // batches get to run, in order to make sure that all diagnostics emitted
    // during the compilation end up in at least one serialized diagnostic file.
    // Therefore, treat batch mode as implying -continue-building-after-errors.
    // (This behavior could be limited to only when serialized diagnostics are
    // being emitted, but this seems more consistent and less surprising for
    // users.)
    // FIXME: We don't really need (or want) a full ContinueBuildingAfterErrors.
    // If we fail to precompile a bridging header, for example, there's no need
    // to go on to compilation of source files, and if compilation of source files
    // fails, we shouldn't try to link. Instead, we'd want to let all jobs finish
    // but not schedule any new ones.
    return compilerMode.isBatchCompile || parsedOptions.contains(.continueBuildingAfterErrors)
  }
}


extension Diagnostic.Message {
  static func remark_max_determinism_overriding(_ option: Option) -> Diagnostic.Message {
    .remark("SWIFTC_MAXIMUM_DETERMINISM overriding \(option.spelling)")
  }
}

// Debug information
extension Driver {
  /// Compute the level of debug information we are supposed to produce.
  private static func computeDebugInfo(_ parsedOptions: inout ParsedOptions,
                                       defaultDwarfVersion : UInt8,
                                       diagnosticsEngine: DiagnosticsEngine) -> DebugInfo {
    var shouldVerify = parsedOptions.hasArgument(.verifyDebugInfo)

    for debugPrefixMap in parsedOptions.arguments(for: .debugPrefixMap) {
      let value = debugPrefixMap.argument.asSingle
      let parts = value.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      if parts.count != 2 {
        diagnosticsEngine.emit(.error_opt_invalid_mapping(option: debugPrefixMap.option, value: value))
      }
    }

    for filePrefixMap in parsedOptions.arguments(for: .filePrefixMap) {
      let value = filePrefixMap.argument.asSingle
      let parts = value.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      if parts.count != 2 {
        diagnosticsEngine.emit(.error_opt_invalid_mapping(option: filePrefixMap.option, value: value))
      }
    }

    // Determine the debug level.
    let level: DebugInfo.Level?
    if let levelOption = parsedOptions.getLast(in: .g), levelOption.option != .gnone {
      switch levelOption.option {
      case .g:
        level = .astTypes

      case .glineTablesOnly:
        level = .lineTables

      case .gdwarfTypes:
        level = .dwarfTypes

      default:
        fatalError("Unhandle option in the '-g' group")
      }
    } else {
      // -gnone, or no debug level specified
      level = nil
      if shouldVerify {
        shouldVerify = false
        diagnosticsEngine.emit(.verify_debug_info_requires_debug_option)
      }
    }

    // Determine the debug info format.
    let format: DebugInfo.Format
    if let formatArg = parsedOptions.getLastArgument(.debugInfoFormat) {
      if let parsedFormat = DebugInfo.Format(rawValue: formatArg.asSingle) {
        format = parsedFormat
      } else {
        diagnosticsEngine.emit(.error_invalid_arg_value(arg: .debugInfoFormat, value: formatArg.asSingle))
        format = .dwarf
      }

      if !parsedOptions.contains(in: .g) {
        diagnosticsEngine.emit(.error_option_missing_required_argument(option: .debugInfoFormat, requiredArg: "-g"))
      }
    } else {
      // Default to DWARF.
      format = .dwarf
    }

    if format == .codeView && (level == .lineTables || level == .dwarfTypes) {
      let levelOption = parsedOptions.getLast(in: .g)!.option
      let fullNotAllowedOption = Option.debugInfoFormat.spelling + format.rawValue
      diagnosticsEngine.emit(.error_argument_not_allowed_with(arg: fullNotAllowedOption, other: levelOption.spelling))
    }

    // Determine the DWARF version.
    var dwarfVersion: UInt8 = defaultDwarfVersion
    if let versionArg = parsedOptions.getLastArgument(.dwarfVersion) {
      if let parsedVersion = UInt8(versionArg.asSingle), parsedVersion >= 2 && parsedVersion <= 5 {
        dwarfVersion = parsedVersion
      } else {
        diagnosticsEngine.emit(.error_invalid_arg_value(arg: .dwarfVersion, value: versionArg.asSingle))
      }
    }

    return DebugInfo(format: format, dwarfVersion: dwarfVersion, level: level, shouldVerify: shouldVerify)
  }

  /// Parses the set of `-sanitize={sanitizer}` arguments and returns all the
  /// sanitizers that were requested.
  static func parseSanitizerArgValues(
    _ parsedOptions: inout ParsedOptions,
    diagnosticEngine: DiagnosticsEngine,
    toolchain: Toolchain,
    targetInfo: FrontendTargetInfo
  ) throws -> Set<Sanitizer> {

    var set = Set<Sanitizer>()

    let args = parsedOptions
      .filter { $0.option == .sanitizeEQ }
      .flatMap { $0.argument.asMultiple }

    // No sanitizer args found, we could return.
    if args.isEmpty {
      return set
    }

    let targetTriple = targetInfo.target.triple
    // Find the sanitizer kind.
    for arg in args {
      guard let sanitizer = Sanitizer(rawValue: arg) else {
        // Unrecognized sanitizer option
        diagnosticEngine.emit(
          .error_invalid_arg_value(arg: .sanitizeEQ, value: arg))
        continue
      }

      let stableAbi = sanitizer == .address && parsedOptions.contains(.sanitizeStableAbiEQ)
      // Support is determined by existence of the sanitizer library.
      // FIXME: Should we do this? This prevents cross-compiling with sanitizers
      //        enabled.
      var sanitizerSupported = try toolchain.runtimeLibraryExists(
        for: stableAbi ? .address_stable_abi : sanitizer,
        targetInfo: targetInfo,
        parsedOptions: &parsedOptions,
        isShared: sanitizer != .fuzzer && !stableAbi
      )

      if sanitizer == .thread {
        // TSAN is unavailable on Windows
        if targetTriple.isWindows {
          diagnosticEngine.emit(
            .error_sanitizer_unavailable_on_target(
              sanitizer: "thread",
              target: targetTriple
            )
          )
          continue
        }

        // TSan is explicitly not supported for 32 bits.
        if !targetTriple.arch!.is64Bit {
          sanitizerSupported = false
        }
      }

      if !sanitizerSupported {
        diagnosticEngine.emit(
          .error_unsupported_opt_for_target(
            arg: "-sanitize=\(sanitizer.rawValue)",
            target: targetTriple
          )
        )
      } else {
        set.insert(sanitizer)
      }
    }

    // Check that we're one of the known supported targets for sanitizers.
    if !(targetTriple.isWindows || targetTriple.isDarwin || targetTriple.os == .linux) {
      diagnosticEngine.emit(
        .error_unsupported_opt_for_target(
          arg: "-sanitize=",
          target: targetTriple
        )
      )
    }

    // Address and thread sanitizers can not be enabled concurrently.
    if set.contains(.thread) && set.contains(.address) {
      diagnosticEngine.emit(
        .error_argument_not_allowed_with(
          arg: "-sanitize=thread",
          other: "-sanitize=address"
        )
      )
    }

    // Scudo can only be run with ubsan.
    if set.contains(.scudo) {
      let allowedSanitizers: Set<Sanitizer> = [.scudo, .undefinedBehavior]
      for forbiddenSanitizer in set.subtracting(allowedSanitizers) {
        diagnosticEngine.emit(
          .error_argument_not_allowed_with(
            arg: "-sanitize=scudo",
            other: "-sanitize=\(forbiddenSanitizer.rawValue)"
          )
        )
      }
    }

    return set
  }

}

extension Diagnostic.Message {
  static var verify_debug_info_requires_debug_option: Diagnostic.Message {
    .warning("ignoring '-verify-debug-info'; no debug info is being generated")
  }

  static func warning_option_requires_sanitizer(currentOption: Option, currentOptionValue: String, sanitizerRequired: Sanitizer) -> Diagnostic.Message {
      .warning("option '\(currentOption.spelling)\(currentOptionValue)' has no effect when '\(sanitizerRequired)' sanitizer is disabled. Use \(Option.sanitizeEQ.spelling)\(sanitizerRequired) to enable the sanitizer")
  }
}

// Module computation.
extension Driver {
  /// Compute the base name of the given path without an extension.
  private static func baseNameWithoutExtension(_ path: String) -> String {
    var hasExtension = false
    return baseNameWithoutExtension(path, hasExtension: &hasExtension)
  }

  /// Compute the base name of the given path without an extension.
  private static func baseNameWithoutExtension(_ path: String, hasExtension: inout Bool) -> String {
    if let absolute = try? AbsolutePath(validating: path) {
      hasExtension = absolute.extension != nil
      return absolute.basenameWithoutExt
    }

    if let relative = try? RelativePath(validating: path) {
      hasExtension = relative.extension != nil
      return relative.basenameWithoutExt
    }

    hasExtension = false
    return ""
  }

  /// Determine how the module will be emitted and the name of the module.
  private static func computeModuleInfo(
    _ parsedOptions: inout ParsedOptions,
    compilerOutputType: FileType?,
    compilerMode: CompilerMode,
    linkerOutputType: LinkOutputType?,
    debugInfoLevel: DebugInfo.Level?,
    diagnosticsEngine: DiagnosticsEngine,
    workingDirectory: AbsolutePath?
  ) throws -> ModuleOutputInfo {
    // Figure out what kind of module we will output.
    enum ModuleOutputKind {
      case topLevel
      case auxiliary
    }

    var moduleOutputKind: ModuleOutputKind?
    if parsedOptions.hasArgument(.emitModule, .emitModulePath) {
      // The user has requested a module, so generate one and treat it as
      // top-level output.
      moduleOutputKind = .topLevel
    } else if (debugInfoLevel?.requiresModule ?? false) && linkerOutputType != nil {
      // An option has been passed which requires a module, but the user hasn't
      // requested one. Generate a module, but treat it as an intermediate output.
      moduleOutputKind = .auxiliary
    } else if parsedOptions.hasArgument(.emitObjcHeader, .emitObjcHeaderPath,
                                        .emitModuleInterface, .emitModuleInterfacePath,
                                        .emitPrivateModuleInterfacePath, .emitPackageModuleInterfacePath) {
      // An option has been passed which requires whole-module knowledge, but we
      // don't have that. Generate a module, but treat it as an intermediate
      // output.
      moduleOutputKind = .auxiliary
    } else {
      // No options require a module, so don't generate one.
      moduleOutputKind = nil
    }

    // The REPL and immediate mode do not support module output
    if moduleOutputKind != nil && (compilerMode == .repl || compilerMode == .immediate || compilerMode == .intro) {
      diagnosticsEngine.emit(.error_mode_cannot_emit_module)
      moduleOutputKind = nil
    }

    // Determine the name of the module.
    var moduleName: String
    var moduleNameIsFallback = false
    if let arg = parsedOptions.getLastArgument(.moduleName) {
      moduleName = arg.asSingle
    } else if compilerMode == .repl || compilerMode == .intro {
      // TODO: Remove the `.intro` check once the REPL no longer launches
      // by default.
      // REPL mode should always use the REPL module.
      moduleName = "REPL"
    } else if let outputArg = parsedOptions.getLastArgument(.o) {
      var hasExtension = false
      var rawModuleName = baseNameWithoutExtension(outputArg.asSingle, hasExtension: &hasExtension)
      if (linkerOutputType == .dynamicLibrary || linkerOutputType == .staticLibrary) &&
        hasExtension && rawModuleName.starts(with: "lib") {
        // Chop off a "lib" prefix if we're building a library.
        rawModuleName = String(rawModuleName.dropFirst(3))
      }

      moduleName = rawModuleName
    } else if parsedOptions.allInputs.count == 1 {
      moduleName = baseNameWithoutExtension(parsedOptions.allInputs.first!)
    } else {
      // This value will fail the isSwiftIdentifier test below.
      moduleName = ""
    }

    func fallbackOrDiagnose(_ error: Diagnostic.Message) {
      moduleNameIsFallback = true
      if compilerOutputType == nil || !parsedOptions.hasArgument(.moduleName) {
        moduleName = "main"
      } else {
        diagnosticsEngine.emit(error)
        moduleName = "__bad__"
      }
    }

    if !moduleName.sd_isSwiftIdentifier {
      fallbackOrDiagnose(.error_bad_module_name(moduleName: moduleName, explicitModuleName: parsedOptions.contains(.moduleName)))
    } else if moduleName == "Swift" && !parsedOptions.contains(.parseStdlib) {
      fallbackOrDiagnose(.error_stdlib_module_name(moduleName: moduleName, explicitModuleName: parsedOptions.contains(.moduleName)))
    }

    // Retrieve and validate module aliases if passed in
    let moduleAliases = moduleAliasesFromInput(parsedOptions.arguments(for: [.moduleAlias]), with: moduleName, onError: diagnosticsEngine)

    // If we're not emitting a module, we're done.
    if moduleOutputKind == nil {
      return ModuleOutputInfo(output: nil, name: moduleName, nameIsFallback: moduleNameIsFallback, aliases: moduleAliases)
    }

    // Determine the module file to output.
    var moduleOutputPath: VirtualPath

    // FIXME: Look in the output file map. It looks like it is weirdly
    // anchored to the first input?
    if let modulePathArg = parsedOptions.getLastArgument(.emitModulePath) {
      // The module path was specified.
      moduleOutputPath = try VirtualPath(path: modulePathArg.asSingle)
    } else if moduleOutputKind == .topLevel {
      // FIXME: Logic to infer from primary outputs, etc.
      let moduleFilename = moduleName.appendingFileTypeExtension(.swiftModule)
      if let outputArg = parsedOptions.getLastArgument(.o)?.asSingle, compilerOutputType == .swiftModule {
        // If the module is the primary output, match -o exactly if present.
        moduleOutputPath = try .init(path: outputArg)
      } else if let outputArg = parsedOptions.getLastArgument(.o)?.asSingle, let lastSeparatorIndex = outputArg.lastIndex(of: "/") {
        // Put the module next to the top-level output.
        moduleOutputPath = try .init(path: outputArg[outputArg.startIndex...lastSeparatorIndex] + moduleFilename)
      } else {
        moduleOutputPath = try .init(path: moduleFilename)
      }
    } else {
      moduleOutputPath = try VirtualPath.createUniqueTemporaryFile(RelativePath(validating: moduleName.appendingFileTypeExtension(.swiftModule)))
    }

    // Use working directory if specified
    if let moduleRelative = moduleOutputPath.relativePath {
      moduleOutputPath = try Driver.useWorkingDirectory(moduleRelative, workingDirectory)
    }

    switch moduleOutputKind! {
    case .topLevel:
      return ModuleOutputInfo(output: .topLevel(moduleOutputPath.intern()), name: moduleName, nameIsFallback: moduleNameIsFallback, aliases: moduleAliases)
    case .auxiliary:
      return ModuleOutputInfo(output: .auxiliary(moduleOutputPath.intern()), name: moduleName, nameIsFallback: moduleNameIsFallback, aliases: moduleAliases)
    }
  }

  // Validate and return module aliases passed via -module-alias
  static func moduleAliasesFromInput(_ aliasArgs: [ParsedOption],
                                     with moduleName: String,
                                     onError diagnosticsEngine: DiagnosticsEngine) -> [String: String]? {
    var moduleAliases: [String: String]? = nil
    let validate = { (_ arg: String, allowModuleName: Bool) -> Bool in
      if !arg.sd_isSwiftIdentifier {
        diagnosticsEngine.emit(.error_bad_module_name(moduleName: arg, explicitModuleName: true))
        return false
      }
      if arg == "Swift" {
        diagnosticsEngine.emit(.error_stdlib_module_name(moduleName: arg, explicitModuleName: true))
        return false
      }
      if !allowModuleName, arg == moduleName {
        diagnosticsEngine.emit(.error_bad_module_alias(arg, moduleName: moduleName))
        return false
      }
      return true
    }

    var used = [""]
    for item in aliasArgs {
      let arg = item.argument.asSingle
      let pair = arg.components(separatedBy: "=")
      guard pair.count == 2 else {
        diagnosticsEngine.emit(.error_bad_module_alias(arg, moduleName: moduleName, formatted: false))
        continue
      }
      guard let lhs = pair.first, validate(lhs, false) else { continue }
      guard let rhs = pair.last, validate(rhs, true) else { continue }

      if moduleAliases == nil {
        moduleAliases = [String: String]()
      }
      if let _ = moduleAliases?[lhs] {
        diagnosticsEngine.emit(.error_bad_module_alias(lhs, moduleName: moduleName, isDuplicate: true))
        continue
      }
      if used.contains(rhs)  {
        diagnosticsEngine.emit(.error_bad_module_alias(rhs, moduleName: moduleName, isDuplicate: true))
        continue
      }
      moduleAliases?[lhs] = rhs
      used.append(lhs)
      used.append(rhs)
    }
    return moduleAliases
  }
}

// SDK computation.
extension Driver {
  /// Computes the path to the SDK.
  private static func computeSDKPath(
    _ parsedOptions: inout ParsedOptions,
    compilerMode: CompilerMode,
    toolchain: Toolchain,
    targetTriple: Triple?,
    fileSystem: FileSystem,
    diagnosticsEngine: DiagnosticsEngine,
    env: [String: String]
  ) -> VirtualPath? {
    var sdkPath: String?

    if let arg = parsedOptions.getLastArgument(.sdk) {
      sdkPath = arg.asSingle
    } else if let SDKROOT = env["SDKROOT"] {
      sdkPath = SDKROOT
    } else if compilerMode == .immediate || compilerMode == .repl {
      // In immediate modes, query the toolchain for a default SDK.
      sdkPath = try? toolchain.defaultSDKPath(targetTriple)?.pathString
    }

    // An empty string explicitly clears the SDK.
    if sdkPath == "" {
      sdkPath = nil
    }

    // Delete trailing /.
    sdkPath = sdkPath.map { $0.count > 1 && $0.last == "/" ? String($0.dropLast()) : $0 }

    // Validate the SDK if we found one.
    if let sdkPath = sdkPath {
      let path: AbsolutePath

      // FIXME: TSC should provide a better utility for this.
      if let absPath = try? AbsolutePath(validating: sdkPath) {
        path = absPath
      } else if let cwd = fileSystem.currentWorkingDirectory, let absPath = try? AbsolutePath(validating: sdkPath, relativeTo: cwd) {
        path = absPath
      } else {
        diagnosticsEngine.emit(.warning_no_such_sdk(sdkPath))
        return nil
      }

      if !fileSystem.exists(path) {
        diagnosticsEngine.emit(.warning_no_such_sdk(sdkPath))
      } else if !(targetTriple?.isWindows ?? (defaultToolchainType == WindowsToolchain.self)) {
        if isSDKTooOld(sdkPath: path, fileSystem: fileSystem,
                       diagnosticsEngine: diagnosticsEngine) {
          diagnosticsEngine.emit(.error_sdk_too_old(sdkPath))
          return nil
        }
      }

      return .absolute(path)
    }

    return nil
  }
}

// SDK checking: attempt to diagnose if the SDK we are pointed at is too old.
extension Driver {
  static func isSDKTooOld(sdkPath: AbsolutePath, fileSystem: FileSystem,
                          diagnosticsEngine: DiagnosticsEngine) -> Bool {
    let sdkInfoReadAttempt = DarwinToolchain.readSDKInfo(fileSystem, VirtualPath.absolute(sdkPath).intern())
    guard let sdkInfo = sdkInfoReadAttempt else {
      diagnosticsEngine.emit(.warning_no_sdksettings_json(sdkPath.pathString))
      return false
    }
    guard let sdkVersion = try? Version(string: sdkInfo.versionString, lenient: true) else {
      diagnosticsEngine.emit(.warning_fail_parse_sdk_ver(sdkInfo.versionString, sdkPath.pathString))
      return false
    }
    if sdkInfo.canonicalName.hasPrefix("macos") {
      return sdkVersion < Version(10, 15, 0)
    } else if sdkInfo.canonicalName.hasPrefix("iphone") ||
                sdkInfo.canonicalName.hasPrefix("appletv") {
      return sdkVersion < Version(13, 0, 0)
    } else if sdkInfo.canonicalName.hasPrefix("watch") {
      return sdkVersion < Version(6, 0, 0)
    } else {
      return false
    }
  }
}

// Imported Objective-C header.
extension Driver {
  /// Compute the path of the imported Objective-C header.
  static func computeImportedObjCHeader(
    _ parsedOptions: inout ParsedOptions,
    compilerMode: CompilerMode,
    diagnosticEngine: DiagnosticsEngine
  ) throws -> VirtualPath.Handle? {
    guard let objcHeaderPathArg = parsedOptions.getLastArgument(.importObjcHeader) else {
      return nil
    }

    // Check for conflicting options.
    if parsedOptions.hasArgument(.importUnderlyingModule) {
      diagnosticEngine.emit(.error_framework_bridging_header)
    }

    if parsedOptions.hasArgument(.emitModuleInterface, .emitModuleInterfacePath) {
      diagnosticEngine.emit(.error_bridging_header_module_interface)
    }

    return try VirtualPath.intern(path: objcHeaderPathArg.asSingle)
  }

  /// Compute the path of the generated bridging PCH for the Objective-C header.
  static func computeBridgingPrecompiledHeader(_ parsedOptions: inout ParsedOptions,
                                               compilerMode: CompilerMode,
                                               importedObjCHeader: VirtualPath.Handle?,
                                               outputFileMap: OutputFileMap?,
                                               contextHash: String?) -> VirtualPath.Handle? {
    guard compilerMode.supportsBridgingPCH,
      let input = importedObjCHeader,
      parsedOptions.hasFlag(positive: .enableBridgingPch, negative: .disableBridgingPch, default: true) else {
        return nil
    }

    if let outputPath = try? outputFileMap?.existingOutput(inputFile: input, outputType: .pch) {
      return outputPath
    }

    let pchFile : String
    let baseName = VirtualPath.lookup(input).basenameWithoutExt
    if let hash = contextHash {
      pchFile = baseName + "-" + hash + ".pch"
    } else {
      pchFile = baseName.appendingFileTypeExtension(.pch)
    }
    if let outputDirectory = parsedOptions.getLastArgument(.pchOutputDir)?.asSingle {
      return try? VirtualPath(path: outputDirectory).appending(component: pchFile).intern()
    } else {
      return try? VirtualPath.temporary(RelativePath(validating: pchFile)).intern()
    }
  }
}

extension Diagnostic.Message {
  static var error_framework_bridging_header: Diagnostic.Message {
    .error("using bridging headers with framework targets is unsupported")
  }

  static var error_bridging_header_module_interface: Diagnostic.Message {
    .error("using bridging headers with module interfaces is unsupported")
  }
  static func warning_cannot_assign_to_compilation_condition(name: String) -> Diagnostic.Message {
    .warning("conditional compilation flags do not have values in Swift; they are either present or absent (rather than '\(name)')")
  }
  static func warning_framework_search_path_includes_extension(path: String) -> Diagnostic.Message {
    .warning("framework search path ends in \".framework\"; add directory containing framework instead: \(path)")
  }
}

// MARK: Miscellaneous Argument Validation
extension Driver {
  static func validateWarningControlArgs(_ parsedOptions: inout ParsedOptions,
                                         diagnosticEngine: DiagnosticsEngine) {
    if parsedOptions.hasArgument(.suppressWarnings) &&
        parsedOptions.hasFlag(positive: .warningsAsErrors, negative: .noWarningsAsErrors, default: false) {
      diagnosticEngine.emit(.error(Error.conflictingOptions(.warningsAsErrors, .suppressWarnings)),
                            location: nil)
    }
  }

  static func validateDigesterArgs(_ parsedOptions: inout ParsedOptions,
                                   moduleOutputInfo: ModuleOutputInfo,
                                   digesterMode: DigesterMode,
                                   swiftInterfacePath: VirtualPath.Handle?,
                                   diagnosticEngine: DiagnosticsEngine) {
    if moduleOutputInfo.output?.isTopLevel != true {
      for arg in parsedOptions.arguments(for: .emitDigesterBaseline, .emitDigesterBaselinePath, .compareToBaselinePath) {
        diagnosticEngine.emit(.error(Error.baselineGenerationRequiresTopLevelModule(arg.option.spelling)),
                              location: nil)
      }
    }

    if parsedOptions.hasArgument(.serializeBreakingChangesPath) && !parsedOptions.hasArgument(.compareToBaselinePath) {
      diagnosticEngine.emit(.error(Error.optionRequiresAnother(Option.serializeBreakingChangesPath.spelling,
                                                               Option.compareToBaselinePath.spelling)),
                            location: nil)
    }
    if parsedOptions.hasArgument(.digesterBreakageAllowlistPath) && !parsedOptions.hasArgument(.compareToBaselinePath) {
      diagnosticEngine.emit(.error(Error.optionRequiresAnother(Option.digesterBreakageAllowlistPath.spelling,
                                                               Option.compareToBaselinePath.spelling)),
                            location: nil)
    }
    if digesterMode == .abi && !parsedOptions.hasArgument(.enableLibraryEvolution) {
      diagnosticEngine.emit(.error(Error.optionRequiresAnother("\(Option.digesterMode.spelling) abi",
                                                               Option.enableLibraryEvolution.spelling)),
                            location: nil)
    }
    if digesterMode == .abi && swiftInterfacePath == nil {
      diagnosticEngine.emit(.error(Error.optionRequiresAnother("\(Option.digesterMode.spelling) abi",
                                                               Option.emitModuleInterface.spelling)),
                            location: nil)
    }
  }

  static func validateValidateClangModulesOnceOptions(_ parsedOptions: inout ParsedOptions,
                                                      diagnosticEngine: DiagnosticsEngine) {
    // '-validate-clang-modules-once' requires '-clang-build-session-file'
    if parsedOptions.hasArgument(.validateClangModulesOnce) &&
        !parsedOptions.hasArgument(.clangBuildSessionFile) {
      diagnosticEngine.emit(.error(Error.optionRequiresAnother(Option.validateClangModulesOnce.spelling,
                                                               Option.clangBuildSessionFile.spelling)),
                            location: nil)
    }
  }

  static func validateEmitDependencyGraphArgs(_ parsedOptions: inout ParsedOptions,
                                              diagnosticEngine: DiagnosticsEngine) {
    // '-print-explicit-dependency-graph' requires '-explicit-module-build'
    if parsedOptions.hasArgument(.printExplicitDependencyGraph) &&
        !parsedOptions.hasArgument(.driverExplicitModuleBuild) {
      diagnosticEngine.emit(.error(Error.optionRequiresAnother(Option.printExplicitDependencyGraph.spelling,
                                                               Option.driverExplicitModuleBuild.spelling)),
                            location: nil)
    }
    // '-explicit-dependency-graph-format=' requires '-print-explicit-dependency-graph'
    if parsedOptions.hasArgument(.explicitDependencyGraphFormat) &&
        !parsedOptions.hasArgument(.printExplicitDependencyGraph) {
      diagnosticEngine.emit(.error(Error.optionRequiresAnother(Option.explicitDependencyGraphFormat.spelling,
                                                               Option.printExplicitDependencyGraph.spelling)),
                            location: nil)
    }
    // '-explicit-dependency-graph-format=' only supports values 'json' and 'dot'
    if let formatArg = parsedOptions.getLastArgument(.explicitDependencyGraphFormat)?.asSingle {
      if formatArg != "json" && formatArg != "dot" {
        diagnosticEngine.emit(.error_unsupported_argument(argument: formatArg,
                                                          option: .explicitDependencyGraphFormat))
      }
    }
  }

  static func validateProfilingArgs(_ parsedOptions: inout ParsedOptions,
                                    fileSystem: FileSystem,
                                    workingDirectory: AbsolutePath?,
                                    diagnosticEngine: DiagnosticsEngine) {
    if parsedOptions.hasArgument(.profileGenerate) &&
        parsedOptions.hasArgument(.profileUse) {
      diagnosticEngine.emit(.error(Error.conflictingOptions(.profileGenerate, .profileUse)),
                            location: nil)
    }

    if let profileArgs = parsedOptions.getLastArgument(.profileUse)?.asMultiple,
       let workingDirectory = workingDirectory {
      for profilingData in profileArgs {
        if let path = try? AbsolutePath(validating: profilingData,
                                          relativeTo: workingDirectory) {
          if !fileSystem.exists(path) {
            diagnosticEngine.emit(.error(Error.missingProfilingData(profilingData)),
                                  location: nil)
          }
        }
      }
    }
  }

  static func validateParseableOutputArgs(_ parsedOptions: inout ParsedOptions,
                                          diagnosticEngine: DiagnosticsEngine) {
    if parsedOptions.contains(.parseableOutput) &&
        parsedOptions.contains(.useFrontendParseableOutput) {
      diagnosticEngine.emit(.error(Error.conflictingOptions(.parseableOutput, .useFrontendParseableOutput)),
                            location: nil)
    }
  }

  static func validateCompilationConditionArgs(_ parsedOptions: inout ParsedOptions,
                                               diagnosticEngine: DiagnosticsEngine) {
    for arg in parsedOptions.arguments(for: .D).map(\.argument.asSingle) {
      if arg.contains("=") {
        diagnosticEngine.emit(.warning_cannot_assign_to_compilation_condition(name: arg))
      } else if arg.hasPrefix("-D") {
        diagnosticEngine.emit(.error(Error.conditionalCompilationFlagHasRedundantPrefix(arg)),
                              location: nil)
      } else if !arg.sd_isSwiftIdentifier {
        diagnosticEngine.emit(.error(Error.conditionalCompilationFlagIsNotValidIdentifier(arg)),
                              location: nil)
      }
    }
  }

  static func validateFrameworkSearchPathArgs(_ parsedOptions: inout ParsedOptions,
                                              diagnosticEngine: DiagnosticsEngine) {
    for arg in parsedOptions.arguments(for: .F, .Fsystem).map(\.argument.asSingle) {
      if arg.hasSuffix(".framework") || arg.hasSuffix(".framework/") {
        diagnosticEngine.emit(.warning_framework_search_path_includes_extension(path: arg))
      }
    }
  }

  private static func validateCoverageArgs(_ parsedOptions: inout ParsedOptions, diagnosticsEngine: DiagnosticsEngine) {
    for coveragePrefixMap in parsedOptions.arguments(for: .coveragePrefixMap) {
      let value = coveragePrefixMap.argument.asSingle
      let parts = value.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      if parts.count != 2 {
        diagnosticsEngine.emit(.error_opt_invalid_mapping(option: coveragePrefixMap.option, value: value))
      }
    }
  }

  private static func validateLinkArgs(_ parsedOptions: inout ParsedOptions, diagnosticsEngine: DiagnosticsEngine) {
    if parsedOptions.hasArgument(.experimentalHermeticSealAtLink) {
      if parsedOptions.hasArgument(.enableLibraryEvolution) {
        diagnosticsEngine.emit(.error_hermetic_seal_cannot_have_library_evolution)
      }

      let lto = Self.ltoKind(&parsedOptions, diagnosticsEngine: diagnosticsEngine)
      if lto == nil {
        diagnosticsEngine.emit(.error_hermetic_seal_requires_lto)
      }
    }
    if parsedOptions.hasArgument(.linkObjcRuntime) ||
        parsedOptions.hasArgument(.noLinkObjcRuntime) {
      diagnosticsEngine.emit(.warning_darwin_link_objc_deprecated())
    }
  }

  private static func validateSanitizerAddressUseOdrIndicatorFlag(
    _ parsedOptions: inout ParsedOptions,
    diagnosticEngine: DiagnosticsEngine,
    addressSanitizerEnabled: Bool
  ) {
    if (parsedOptions.hasArgument(.sanitizeAddressUseOdrIndicator) && !addressSanitizerEnabled) {
      diagnosticEngine.emit(
        .warning_option_requires_sanitizer(currentOption: .sanitizeAddressUseOdrIndicator, currentOptionValue: "", sanitizerRequired: .address))
    }
  }

  private static func validateSanitizeStableABI(
          _ parsedOptions: inout ParsedOptions,
          diagnosticEngine: DiagnosticsEngine,
          addressSanitizerEnabled: Bool
          ) {
      if (parsedOptions.hasArgument(.sanitizeStableAbiEQ) && !addressSanitizerEnabled) {
          diagnosticEngine.emit(
                  .warning_option_requires_sanitizer(currentOption: .sanitizeStableAbiEQ, currentOptionValue: "", sanitizerRequired: .address))
      }
  }

  /// Validates the set of `-sanitize-recover={sanitizer}` arguments
  private static func validateSanitizerRecoverArgValues(
    _ parsedOptions: inout ParsedOptions,
    diagnosticEngine: DiagnosticsEngine,
    enabledSanitizers: Set<Sanitizer>
  ){
    let args = parsedOptions
      .filter { $0.option == .sanitizeRecoverEQ }
      .flatMap { $0.argument.asMultiple }

    // No sanitizer args found, we could return.
    if args.isEmpty {
      return
    }

    // Find the sanitizer kind.
    for arg in args {
      guard let sanitizer = Sanitizer(rawValue: arg) else {
        // Unrecognized sanitizer option
        diagnosticEngine.emit(
          .error_invalid_arg_value(arg: .sanitizeRecoverEQ, value: arg))
        continue
      }

      // only -sanitize-recover=address is supported
      if sanitizer != .address {
        diagnosticEngine.emit(
          .error_unsupported_argument(argument: arg, option: .sanitizeRecoverEQ))
        continue
      }

      if !enabledSanitizers.contains(sanitizer) {
        diagnosticEngine.emit(
          .warning_option_requires_sanitizer(currentOption: .sanitizeRecoverEQ, currentOptionValue: arg, sanitizerRequired: sanitizer))
      }
    }
  }

  private static func validateSanitizerCoverageArgs(_ parsedOptions: inout ParsedOptions,
                                                    anySanitizersEnabled: Bool,
                                                    diagnosticsEngine: DiagnosticsEngine) {
    var foundRequiredArg = false
    for arg in parsedOptions.arguments(for: .sanitizeCoverageEQ).flatMap(\.argument.asMultiple) {
      if ["func", "bb", "edge"].contains(arg) {
        foundRequiredArg = true
      } else if !["indirect-calls", "trace-bb", "trace-cmp", "8bit-counters", "trace-pc", "trace-pc-guard"].contains(arg) {
        diagnosticsEngine.emit(.error_unsupported_argument(argument: arg, option: .sanitizeCoverageEQ))
      }

      if !foundRequiredArg {
        diagnosticsEngine.emit(.error_option_missing_required_argument(option: .sanitizeCoverageEQ,
                                                                       requiredArg: #""func", "bb", "edge""#))
      }
    }

    if parsedOptions.hasArgument(.sanitizeCoverageEQ) && !anySanitizersEnabled {
      diagnosticsEngine.emit(.error_option_requires_sanitizer(option: .sanitizeCoverageEQ))
    }
  }
}

extension Triple {
  @_spi(Testing) public func toolchainType(_ diagnosticsEngine: DiagnosticsEngine) throws -> Toolchain.Type {
    switch os {
    case .darwin, .macosx, .ios, .tvos, .watchos, .visionos:
      return DarwinToolchain.self
    case .linux:
      return GenericUnixToolchain.self
    case .freeBSD, .haiku, .openbsd:
      return GenericUnixToolchain.self
    case .wasi:
      return WebAssemblyToolchain.self
    case .win32:
      return WindowsToolchain.self
    case .noneOS:
        switch self.vendor {
        case .apple:
            return DarwinToolchain.self
        default:
            return GenericUnixToolchain.self
        }
    default:
      diagnosticsEngine.emit(.error_unknown_target(triple))
      throw Driver.ErrorDiagnostics.emitted
    }
  }
}

/// Toolchain computation.
extension Driver {
  #if canImport(Darwin)
  static let defaultToolchainType: Toolchain.Type = DarwinToolchain.self
  #elseif os(Windows)
  static let defaultToolchainType: Toolchain.Type = WindowsToolchain.self
  #else
  static let defaultToolchainType: Toolchain.Type = GenericUnixToolchain.self
  #endif

  static func computeHostTriple(
    _ parsedOptions: inout ParsedOptions,
    diagnosticsEngine: DiagnosticsEngine,
    toolchain: Toolchain,
    executor: DriverExecutor,
    fileSystem: FileSystem,
    workingDirectory: AbsolutePath?,
    swiftCompilerPrefixArgs: [String]) throws -> Triple {

    let frontendOverride = try FrontendOverride(&parsedOptions, diagnosticsEngine)
    frontendOverride.setUpForTargetInfo(toolchain)
    defer { frontendOverride.setUpForCompilation(toolchain) }
    return try Self.computeTargetInfo(target: nil, targetVariant: nil,
                                      swiftCompilerPrefixArgs: frontendOverride.prefixArgsForTargetInfo,
                                      toolchain: toolchain, fileSystem: fileSystem,
                                      workingDirectory: workingDirectory,
                                      diagnosticsEngine: diagnosticsEngine,
                                      executor: executor).target.triple
  }

  static func computeToolchain(
    _ parsedOptions: inout ParsedOptions,
    diagnosticsEngine: DiagnosticsEngine,
    compilerMode: CompilerMode,
    env: [String: String],
    executor: DriverExecutor,
    fileSystem: FileSystem,
    useStaticResourceDir: Bool,
    workingDirectory: AbsolutePath?,
    compilerExecutableDir: AbsolutePath?
  ) throws -> (Toolchain, FrontendTargetInfo, [String]) {
    let explicitTarget = (parsedOptions.getLastArgument(.target)?.asSingle)
      .map {
        Triple($0, normalizing: true)
      }
    let explicitTargetVariant = (parsedOptions.getLastArgument(.targetVariant)?.asSingle)
      .map {
        Triple($0, normalizing: true)
      }

    // Determine the resource directory.
    let resourceDirPath: VirtualPath?
    if let resourceDirArg = parsedOptions.getLastArgument(.resourceDir) {
      resourceDirPath = try VirtualPath(path: resourceDirArg.asSingle)
    } else {
      resourceDirPath = nil
    }

    let toolchainType = try explicitTarget?.toolchainType(diagnosticsEngine) ??
          defaultToolchainType
    // Find tools directory and pass it down to the toolchain
    var toolDir: AbsolutePath?
    if let td = parsedOptions.getLastArgument(.toolsDirectory) {
      toolDir = try AbsolutePath(validating: td.asSingle)
    }
    let toolchain = toolchainType.init(env: env, executor: executor,
                                       fileSystem: fileSystem,
                                       compilerExecutableDir: compilerExecutableDir,
                                       toolDirectory: toolDir)

    let frontendOverride = try FrontendOverride(&parsedOptions, diagnosticsEngine)
    frontendOverride.setUpForTargetInfo(toolchain)
    defer { frontendOverride.setUpForCompilation(toolchain) }
    // Find the SDK, if any.
    let sdkPath: VirtualPath? = Self.computeSDKPath(
      &parsedOptions, compilerMode: compilerMode, toolchain: toolchain,
      targetTriple: explicitTarget, fileSystem: fileSystem,
      diagnosticsEngine: diagnosticsEngine, env: env)


    // Query the frontend for target information.
    do {
      var info: FrontendTargetInfo =
        try Self.computeTargetInfo(target: explicitTarget, targetVariant: explicitTargetVariant,
                                   sdkPath: sdkPath, resourceDirPath: resourceDirPath,
                                   runtimeCompatibilityVersion:
                                     parsedOptions.getLastArgument(.runtimeCompatibilityVersion)?.asSingle,
                                   useStaticResourceDir: useStaticResourceDir,
                                   swiftCompilerPrefixArgs: frontendOverride.prefixArgsForTargetInfo,
                                   toolchain: toolchain, fileSystem: fileSystem,
                                   workingDirectory: workingDirectory,
                                   diagnosticsEngine: diagnosticsEngine,
                                   executor: executor)

      // Parse the runtime compatibility version. If present, it will override
      // what is reported by the frontend.
      if let versionString =
          parsedOptions.getLastArgument(.runtimeCompatibilityVersion)?.asSingle {
        if let version = SwiftVersion(string: versionString) {
          info.target.swiftRuntimeCompatibilityVersion = version
          info.targetVariant?.swiftRuntimeCompatibilityVersion = version
        } else if (versionString != "none") {
          // "none" was accepted by the old driver, diagnose other values.
          diagnosticsEngine.emit(
            .error_invalid_arg_value(
              arg: .runtimeCompatibilityVersion, value: versionString))
        }
      }

      // Check if the simulator environment was inferred for backwards compatibility.
      if let explicitTarget = explicitTarget,
         explicitTarget.environment != .simulator && info.target.triple.environment == .simulator {
        diagnosticsEngine.emit(.warning_inferring_simulator_target(originalTriple: explicitTarget,
                                                                   inferredTriple: info.target.triple))
      }
      return (toolchain, info, frontendOverride.prefixArgs)
    } catch let JobExecutionError.decodingError(decodingError,
                                                dataToDecode,
                                                processResult) {
      let stringToDecode = String(data: dataToDecode, encoding: .utf8)
      let errorDesc: String
      switch decodingError {
        case let .typeMismatch(type, context):
          errorDesc = "type mismatch: \(type), path: \(context.codingPath)"
        case let .valueNotFound(type, context):
          errorDesc = "value missing: \(type), path: \(context.codingPath)"
        case let .keyNotFound(key, context):
          errorDesc = "key missing: \(key), path: \(context.codingPath)"
       case let .dataCorrupted(context):
          errorDesc = "data corrupted at path: \(context.codingPath)"
        @unknown default:
          errorDesc = "unknown decoding error"
      }
      throw Error.unableToDecodeFrontendTargetInfo(
        stringToDecode,
        processResult.arguments,
        errorDesc)
    } catch let JobExecutionError.jobFailedWithNonzeroExitCode(returnCode, stdout) {
      throw Error.failedToRunFrontendToRetrieveTargetInfo(returnCode, stdout)
    } catch JobExecutionError.failedToReadJobOutput {
      throw Error.unableToReadFrontendTargetInfo
    } catch {
      throw Error.failedToRetrieveFrontendTargetInfo
    }
  }

  internal struct FrontendOverride {
    private let overridePath: AbsolutePath?
    let prefixArgs: [String]

    init() {
      overridePath = nil
      prefixArgs = []
    }

    init(_ parsedOptions: inout ParsedOptions, _ diagnosticsEngine: DiagnosticsEngine) throws {
      guard let arg = parsedOptions.getLastArgument(.driverUseFrontendPath)
      else {
        self = Self()
        return
      }
      let frontendCommandLine = arg.asSingle.split(separator: ";").map { String($0) }
      guard let pathString = frontendCommandLine.first else {
        diagnosticsEngine.emit(.error_no_swift_frontend)
        self = Self()
        return
      }
      overridePath = try AbsolutePath(validating: pathString)
      prefixArgs = frontendCommandLine.dropFirst().map {String($0)}
    }

    var appliesToFetchingTargetInfo: Bool {
      guard let path = overridePath else { return true }
      // lowercased() to handle Python
      // starts(with:) to handle both python3 and point versions (Ex: python3.9). Also future versions (Ex: Python4).
      return !path.basename.lowercased().starts(with: "python")
    }
    func setUpForTargetInfo(_ toolchain: Toolchain) {
      if !appliesToFetchingTargetInfo {
        toolchain.clearKnownToolPath(.swiftCompiler)
      }
    }
    var prefixArgsForTargetInfo: [String] {
      appliesToFetchingTargetInfo ? prefixArgs : []
    }
    func setUpForCompilation(_ toolchain: Toolchain) {
      if let path = overridePath {
        toolchain.overrideToolPath(.swiftCompiler, path: path)
      }
    }
  }
}

// Supplementary outputs.
extension Driver {
  /// Determine the output path for a supplementary output.
  static func computeSupplementaryOutputPath(
    _ parsedOptions: inout ParsedOptions,
    type: FileType,
    isOutputOptions: [Option],
    outputPath: Option,
    compilerOutputType: FileType?,
    compilerMode: CompilerMode,
    emitModuleSeparately: Bool,
    outputFileMap: OutputFileMap?,
    moduleName: String
  ) throws -> VirtualPath.Handle? {
    // If there is an explicit argument for the output path, use that
    if let outputPathArg = parsedOptions.getLastArgument(outputPath) {
      for isOutput in isOutputOptions {
        // Consume the isOutput argument
        _ = parsedOptions.hasArgument(isOutput)
      }
      return try VirtualPath.intern(path: outputPathArg.asSingle)
    }

    // If no output option was provided, don't produce this output at all.
    guard isOutputOptions.contains(where: { parsedOptions.hasArgument($0) }) else {
      return nil
    }

    // If this is a single-file compile and there is an entry in the
    // output file map, use that.
    if compilerMode.isSingleCompilation,
        let singleOutputPath = try outputFileMap?.existingOutputForSingleInput(
            outputType: type) {
      return singleOutputPath
    }

    // The driver lacks a compilerMode for *only* emitting a Swift module, but if the
    // primary output type is a .swiftmodule and we are using the emit-module-separately
    // flow, then also consider single output paths specified in the output file-map.
    if compilerOutputType == .swiftModule && emitModuleSeparately,
       let singleOutputPath = try outputFileMap?.existingOutputForSingleInput(
           outputType: type) {
      return singleOutputPath
    }

    // Emit-module serialized diagnostics are always specified as a single-output
    // file
    if type == .emitModuleDiagnostics,
       let singleOutputPath = try outputFileMap?.existingOutputForSingleInput(
           outputType: type) {
      return singleOutputPath
    }

    // Emit-module discovered dependencies are always specified as a single-output
    // file
    if type == .emitModuleDependencies,
       let path = try outputFileMap?.existingOutputForSingleInput(outputType: type) {
      return path
    }

    // If there is an output argument, derive the name from there.
    if let outputPathArg = parsedOptions.getLastArgument(.o) {
      let path = try VirtualPath(path: outputPathArg.asSingle)

      // If the compiler output is of this type, use the argument directly.
      if type == compilerOutputType {
        return path.intern()
      }

      return path
        .parentDirectory
        .appending(component: "\(moduleName).\(type.rawValue)")
        .intern()
    }

    // If an explicit path is not provided by the output file map, attempt to
    // synthesize a path from the master swift dependency path.  This is
    // important as we may otherwise emit this file at the location where the
    // driver was invoked, which is normally the root of the package.
    if let path = try outputFileMap?.existingOutputForSingleInput(outputType: .swiftDeps) {
      return VirtualPath.lookup(path)
                  .parentDirectory
                  .appending(component: "\(moduleName).\(type.rawValue)")
                  .intern()
    }
    return try VirtualPath.intern(path: moduleName.appendingFileTypeExtension(type))
  }

  /// Determine if the build system has created a Project/ directory for auxiliary outputs.
  static func computeProjectDirectoryPath(moduleOutputPath: VirtualPath.Handle?,
                                          fileSystem: FileSystem) -> VirtualPath.Handle? {
    let potentialProjectDirectory = moduleOutputPath
      .map(VirtualPath.lookup)?
      .parentDirectory
      .appending(component: "Project")
      .absolutePath
    guard let projectDirectory = potentialProjectDirectory, fileSystem.exists(projectDirectory) else {
      return nil
    }
    return VirtualPath.absolute(projectDirectory).intern()
  }

  /// Determine the output path for a module documentation.
  static func computeModuleDocOutputPath(
    _ parsedOptions: inout ParsedOptions,
    moduleOutputPath: VirtualPath.Handle?,
    compilerOutputType: FileType?,
    compilerMode: CompilerMode,
    outputFileMap: OutputFileMap?,
    moduleName: String
  ) throws -> VirtualPath.Handle? {
    return try computeModuleAuxiliaryOutputPath(&parsedOptions,
                                                moduleOutputPath: moduleOutputPath,
                                                type: .swiftDocumentation,
                                                isOutput: .emitModuleDoc,
                                                outputPath: .emitModuleDocPath,
                                                compilerOutputType: compilerOutputType,
                                                compilerMode: compilerMode,
                                                outputFileMap: outputFileMap,
                                                moduleName: moduleName)
  }

  /// Determine the output path for a module source info.
  static func computeModuleSourceInfoOutputPath(
    _ parsedOptions: inout ParsedOptions,
    moduleOutputPath: VirtualPath.Handle?,
    compilerOutputType: FileType?,
    compilerMode: CompilerMode,
    outputFileMap: OutputFileMap?,
    moduleName: String,
    projectDirectory: VirtualPath.Handle?
  ) throws -> VirtualPath.Handle? {
    guard !parsedOptions.hasArgument(.avoidEmitModuleSourceInfo) else { return nil }
    return try computeModuleAuxiliaryOutputPath(&parsedOptions,
                                                moduleOutputPath: moduleOutputPath,
                                                type: .swiftSourceInfoFile,
                                                isOutput: .emitModuleSourceInfo,
                                                outputPath: .emitModuleSourceInfoPath,
                                                compilerOutputType: compilerOutputType,
                                                compilerMode: compilerMode,
                                                outputFileMap: outputFileMap,
                                                moduleName: moduleName,
                                                projectDirectory: projectDirectory)
  }

  static func computeDigesterBaselineOutputPath(
    _ parsedOptions: inout ParsedOptions,
    moduleOutputPath: VirtualPath.Handle?,
    mode: DigesterMode,
    compilerOutputType: FileType?,
    compilerMode: CompilerMode,
    outputFileMap: OutputFileMap?,
    moduleName: String,
    projectDirectory: VirtualPath.Handle?
  ) throws -> VirtualPath.Handle? {
    // Only emit a baseline if at least of the arguments was provided.
    guard parsedOptions.hasArgument(.emitDigesterBaseline, .emitDigesterBaselinePath) else { return nil }
    return try computeModuleAuxiliaryOutputPath(&parsedOptions,
                                                moduleOutputPath: moduleOutputPath,
                                                type: mode.baselineFileType,
                                                isOutput: .emitDigesterBaseline,
                                                outputPath: .emitDigesterBaselinePath,
                                                compilerOutputType: compilerOutputType,
                                                compilerMode: compilerMode,
                                                outputFileMap: outputFileMap,
                                                moduleName: moduleName,
                                                projectDirectory: projectDirectory)
  }



  /// Determine the output path for a module auxiliary output.
  static func computeModuleAuxiliaryOutputPath(
    _ parsedOptions: inout ParsedOptions,
    moduleOutputPath: VirtualPath.Handle?,
    type: FileType,
    isOutput: Option?,
    outputPath: Option,
    compilerOutputType: FileType?,
    compilerMode: CompilerMode,
    outputFileMap: OutputFileMap?,
    moduleName: String,
    projectDirectory: VirtualPath.Handle? = nil
  ) throws -> VirtualPath.Handle? {
    // If there is an explicit argument for the output path, use that
    if let outputPathArg = parsedOptions.getLastArgument(outputPath) {
      // Consume the isOutput argument
      if let isOutput = isOutput {
        _ = parsedOptions.hasArgument(isOutput)
      }
      return try VirtualPath.intern(path: outputPathArg.asSingle)
    }

    // If this is a single-file compile and there is an entry in the
    // output file map, use that.
    if compilerMode.isSingleCompilation,
        let singleOutputPath = try outputFileMap?.existingOutputForSingleInput(
          outputType: type) {
      return singleOutputPath
    }

    // If there's a known module output path, put the file next to it.
    if let moduleOutputPath = moduleOutputPath {
      if let isOutput = isOutput {
        _ = parsedOptions.hasArgument(isOutput)
      }

      let parentPath: VirtualPath
      if let projectDirectory = projectDirectory {
        // If the build system has created a Project dir for us to include the file, use it.
        parentPath = VirtualPath.lookup(projectDirectory)
      } else {
        parentPath = VirtualPath.lookup(moduleOutputPath).parentDirectory
      }

      return try parentPath
        .appending(component: VirtualPath.lookup(moduleOutputPath).basename)
        .replacingExtension(with: type)
        .intern()
    }

    // If the output option was not provided, don't produce this output at all.
    guard let isOutput = isOutput, parsedOptions.hasArgument(isOutput) else {
      return nil
    }

    return try VirtualPath.intern(path: moduleName.appendingFileTypeExtension(type))
  }
}

// CAS and Caching.
extension Driver {
  mutating func getCASPluginPath() throws -> AbsolutePath? {
    if let pluginPath = parsedOptions.getLastArgument(.casPluginPath)?.asSingle {
      return try AbsolutePath(validating: pluginPath.description)
    }
    return try toolchain.lookupToolchainCASPluginLib()
  }

  mutating func getOnDiskCASPath() throws -> AbsolutePath? {
    if let casPathOpt = parsedOptions.getLastArgument(.casPath)?.asSingle {
      return try AbsolutePath(validating: casPathOpt.description)
    }
    return nil;
  }

  mutating func getCASPluginOptions() throws -> [(String, String)] {
    var options : [(String, String)] = []
    for opt in parsedOptions.arguments(for: .casPluginOption) {
      let pluginArg = opt.argument.asSingle.split(separator: "=", maxSplits: 1)
      if pluginArg.count != 2 {
        throw Error.invalidArgumentValue(Option.casPluginOption.spelling, opt.argument.asSingle)
      }
      options.append((String(pluginArg[0]), String(pluginArg[1])))
    }
    return options
  }

  static func computeScanningPrefixMapper(_ parsedOptions: inout ParsedOptions) throws -> [AbsolutePath: AbsolutePath] {
    var mapping: [AbsolutePath: AbsolutePath] = [:]
    for opt in parsedOptions.arguments(for: .scannerPrefixMap) {
      let pluginArg = opt.argument.asSingle.split(separator: "=", maxSplits: 1)
      if pluginArg.count != 2 {
        throw Error.invalidArgumentValue(Option.scannerPrefixMap.spelling, opt.argument.asSingle)
      }
      let key = try AbsolutePath(validating: String(pluginArg[0]))
      let value = try AbsolutePath(validating: String(pluginArg[1]))
      mapping[key] = value
    }
    return mapping
  }
}
