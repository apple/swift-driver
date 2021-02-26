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
import TSCBasic
import TSCUtility
import Foundation
import SwiftOptions

/// The Swift driver.
public struct Driver {
  public enum Error: Swift.Error, Equatable, DiagnosticData {
    case invalidDriverName(String)
    case invalidInput(String)
    case noInputFiles
    case invalidArgumentValue(String, String)
    case relativeFrontendPath(String)
    case subcommandPassedToDriver
    case integratedReplRemoved
    case conflictingOptions(Option, Option)
    case unableToLoadOutputFileMap(String)
    case unableToDecodeFrontendTargetInfo(String?, [String], String)
    case failedToRetrieveFrontendTargetInfo
    case failedToRunFrontendToRetrieveTargetInfo(Int, String?)
    case unableToReadFrontendTargetInfo
    case missingProfilingData(String)
    case conditionalCompilationFlagHasRedundantPrefix(String)
    case conditionalCompilationFlagIsNotValidIdentifier(String)
    // Explicit Module Build Failures
    case malformedModuleDependency(String, String)
    case missingPCMArguments(String)
    case missingModuleDependency(String)
    case dependencyScanningFailure(Int, String)
    case missingExternalDependency(String)

    public var description: String {
      switch self {
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
      case .dependencyScanningFailure(let code, let error):
        return "Module Dependency Scanner returned with non-zero exit status: \(code), \(error)"
      case .unableToLoadOutputFileMap(let path):
        return "unable to load output file map '\(path)': no such file or directory"
      case .missingExternalDependency(let moduleName):
        return "Missing External dependency info for module: \(moduleName)"
      }
    }
  }

  /// The set of environment variables that are visible to the driver and
  /// processes it launches. This is a hook for testing; in actual use
  /// it should be identical to the real environment.
  public let env: [String: String]

  /// Whether we are using the driver as the integrated driver via libSwiftDriver
  public let integratedDriver: Bool

  /// The file system which we should interact with.
  let fileSystem: FileSystem

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
  @_spi(Testing) public let recordedInputModificationDates: [TypedVirtualPath: Date]

  /// The mapping from input files to output files for each kind.
  let outputFileMap: OutputFileMap?

  /// The number of files required before making a file list.
  let fileListThreshold: Int

  /// Should use file lists for inputs (number of inputs exceeds `fileListThreshold`).
  let shouldUseInputFileList: Bool

  /// VirtualPath for shared all sources file list. `nil` if unused.
  @_spi(Testing) public let allSourcesFileList: VirtualPath?

  /// The mode in which the compiler will execute.
  @_spi(Testing) public let compilerMode: CompilerMode

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

  // The information about the module to produce.
  @_spi(Testing) public let moduleOutputInfo: ModuleOutputInfo

  /// Info needed to write and maybe read the build record.
  /// Only present when the driver will be writing the record.
  /// Only used for reading when compiling incrementally.
  let buildRecordInfo: BuildRecordInfo?

  /// A build-record-relative path to the location of a serialized copy of the
  /// driver's dependency graph.
  ///
  /// FIXME: This is a little ridiculous. We could probably just replace the
  /// build record outright with a serialized format.
  var driverDependencyGraphPath: VirtualPath? {
    guard let recordInfo = self.buildRecordInfo else {
      return nil
    }
    let filename = recordInfo.buildRecordPath.basenameWithoutExt
    return recordInfo
      .buildRecordPath
      .parentDirectory
      .appending(component: filename + ".priors")
  }
  
  /// Whether to consider incremental compilation.
  let shouldAttemptIncrementalCompilation: Bool
  
  /// Code & data for incremental compilation. Nil if not running in incremental mode.
  /// Set during planning because needs the jobs to look at outputs.
  @_spi(Testing) public private(set) var incrementalCompilationState: IncrementalCompilationState? = nil

  /// The path of the SDK.
  public var absoluteSDKPath: AbsolutePath? {
    switch frontendTargetInfo.sdkPath?.path {
    case .absolute(let path):
      return path
    case .relative(let path):
      let cwd = workingDirectory ?? fileSystem.currentWorkingDirectory
      return cwd.map { AbsolutePath($0, path) }
    case nil:
      return nil
    case .standardInput, .standardOutput, .temporary, .temporaryWithKnownContents, .fileList:
      fatalError("Frontend target information will never include a path of this type.")
    }
  }

  /// The path to the imported Objective-C header.
  let importedObjCHeader: VirtualPath?

  /// The path to the pch for the imported Objective-C header.
  let bridgingPrecompiledHeader: VirtualPath?

  /// Path to the dependencies file.
  let dependenciesFilePath: VirtualPath?
  
  /// Path to the references dependencies file.
  let referenceDependenciesPath: VirtualPath?

  /// Path to the serialized diagnostics file.
  let serializedDiagnosticsFilePath: VirtualPath?

  /// Path to the Objective-C generated header.
  let objcGeneratedHeaderPath: VirtualPath?

  /// Path to the loaded module trace file.
  let loadedModuleTracePath: VirtualPath?

  /// Path to the TBD file (text-based dylib).
  let tbdPath: VirtualPath?

  /// Path to the module documentation file.
  let moduleDocOutputPath: VirtualPath?

  /// Path to the Swift interface file.
  let swiftInterfacePath: VirtualPath?

  /// Path to the Swift private interface file.
  let swiftPrivateInterfacePath: VirtualPath?

  /// Path to the optimization record.
  let optimizationRecordPath: VirtualPath?

  /// Path to the Swift module source information file.
  let moduleSourceInfoPath: VirtualPath?

  /// Force the driver to emit the module first and then run compile jobs. This could be used to unblock
  /// dependencies in parallel builds.
  var forceEmitModuleBeforeCompile: Bool = false

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

  // TODO: Once the clients have transitioned to using the InterModuleDependencyOracle API,
  // this must convey information about the externally-prebuilt targets only
  /// All external artifacts a build system (e.g. SwiftPM) may pass in as input to the explicit
  /// build of the current module. Consists of a map of externally-built targets, and a map of all previously
  /// discovered/scanned modules and their infos.
  @_spi(Testing) public var externalBuildArtifacts: ExternalBuildArtifacts? = nil

  /// A collection of all the flags the selected toolchain's `swift-frontend` supports
  @_spi(Testing) public let supportedFrontendFlags: Set<String>

  /// Handler for emitting diagnostics to stderr.
  public static let stderrDiagnosticsHandler: DiagnosticsEngine.DiagnosticsHandler = { diagnostic in
    let stream = stderrStream
    if !(diagnostic.location is UnknownLocation) {
      stream <<< diagnostic.location.description <<< ": "
    }

    switch diagnostic.message.behavior {
    case .error:
      stream <<< "error: "
    case .warning:
      stream <<< "warning: "
    case .note:
      stream <<< "note: "
    case .remark:
      stream <<< "remark: "
    case .ignored:
      break
    }

    stream <<< diagnostic.localizedDescription <<< "\n"
    stream.flush()
  }

  /// Create the driver with the given arguments.
  ///
  /// - Parameter args: The command-line arguments, including the "swift" or "swiftc"
  ///   at the beginning.
  /// - Parameter env: The environment variables to use. This is a hook for testing;
  ///   in production, you should use the default argument, which copies the current environment.
  /// - Parameter diagnosticsEngine: The diagnotic engine used by the driver to emit errors
  ///   and warnings.
  /// - Parameter fileSystem: The filesystem used by the driver to find resources/SDKs,
  ///   expand response files, etc. By default this is the local filesystem.
  /// - Parameter executor: Used by the driver to execute jobs. The default argument
  ///   is present to streamline testing, it shouldn't be used in production.
  /// - Parameter externalBuildArtifacts: All external artifacts a build system may pass in as input to the explicit
  ///   build of the current module. Consists of a map of externally-built targets, and a map of all previously
  ///   discovered/scanned modules.
  public init(
    args: [String],
    env: [String: String] = ProcessEnv.vars,
    diagnosticsEngine: DiagnosticsEngine = DiagnosticsEngine(handlers: [Driver.stderrDiagnosticsHandler]),
    fileSystem: FileSystem = localFileSystem,
    executor: DriverExecutor,
    integratedDriver: Bool = true,
    compilerExecutableDir: AbsolutePath? = nil,
    // FIXME: Duplication with externalBuildArtifacts and externalTargetModulePathMap
    // is a temporary backwards-compatibility shim to help transition SwiftPM to the new API
    externalBuildArtifacts: ExternalBuildArtifacts? = nil,
    externalTargetModulePathMap: ExternalTargetModulePathMap? = nil,
    interModuleDependencyOracle: InterModuleDependencyOracle? = nil
  ) throws {
    self.env = env
    self.fileSystem = fileSystem
    self.integratedDriver = integratedDriver

    self.diagnosticEngine = diagnosticsEngine
    self.executor = executor

    if let externalArtifacts = externalBuildArtifacts {
      self.externalBuildArtifacts = externalArtifacts
    } else if let externalTargetPaths = externalTargetModulePathMap {
      self.externalBuildArtifacts = (externalTargetPaths, [:])
    }

    if case .subcommand = try Self.invocationRunMode(forArgs: args).mode {
      throw Error.subcommandPassedToDriver
    }

    var args = try Self.expandResponseFiles(args, fileSystem: fileSystem, diagnosticsEngine: self.diagnosticEngine)

    self.driverKind = try Self.determineDriverKind(args: &args)
    self.optionTable = OptionTable()
    self.parsedOptions = try optionTable.parse(Array(args), for: self.driverKind)
    self.showJobLifecycle = parsedOptions.contains(.driverShowJobLifecycle)

    // Determine the compilation mode.
    self.compilerMode = try Self.computeCompilerMode(&parsedOptions, driverKind: driverKind, diagnosticsEngine: diagnosticEngine)

    self.shouldAttemptIncrementalCompilation = Self.shouldAttemptIncrementalCompilation(&parsedOptions,
                                                                                        diagnosticEngine: diagnosticsEngine,
                                                                                        compilerMode: compilerMode)

    // Compute the working directory.
    workingDirectory = try parsedOptions.getLastArgument(.workingDirectory).map { workingDirectoryArg in
      let cwd = fileSystem.currentWorkingDirectory
      return try cwd.map{ AbsolutePath(workingDirectoryArg.asSingle, relativeTo: $0) } ?? AbsolutePath(validating: workingDirectoryArg.asSingle)
    }

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
          compilerExecutableDir: compilerExecutableDir)

    // Compute the host machine's triple
    self.hostTriple =
      try Self.computeHostTriple(&self.parsedOptions, diagnosticsEngine: diagnosticEngine,
                                 toolchain: self.toolchain, executor: self.executor,
                                 swiftCompilerPrefixArgs: self.swiftCompilerPrefixArgs)

    // Classify and collect all of the input files.
    let inputFiles = try Self.collectInputFiles(&self.parsedOptions, diagnosticsEngine: diagnosticsEngine)
    self.inputFiles = inputFiles
    self.recordedInputModificationDates = .init(uniqueKeysWithValues:
      Set(inputFiles).compactMap {
        guard let modTime = try? fileSystem
          .getFileInfo($0.file).modTime else { return nil }
        return ($0, modTime)
    })

    do {
      let outputFileMap: OutputFileMap?
      // Initialize an empty output file map, which will be populated when we start creating jobs.
      if let outputFileMapArg = parsedOptions.getLastArgument(.outputFileMap)?.asSingle {
        do {
          let path = try VirtualPath(path: outputFileMapArg)
          outputFileMap = try .load(fileSystem: fileSystem, file: path, diagnosticEngine: diagnosticEngine)
        } catch {
          throw Error.unableToLoadOutputFileMap(outputFileMapArg)
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

      // This is a shim for backwards-compatibility with ModuleInfoMap-based API
      // used by SwiftPM
      if let externalArtifacts = externalBuildArtifacts {
        if !externalArtifacts.1.isEmpty {
          try self.interModuleDependencyOracle.mergeModules(from: externalArtifacts.1)
        }
      }
    }

    self.fileListThreshold = try Self.computeFileListThreshold(&self.parsedOptions, diagnosticsEngine: diagnosticsEngine)
    self.shouldUseInputFileList = inputFiles.count > fileListThreshold
    if shouldUseInputFileList {
      let swiftInputs = inputFiles.filter(\.type.isPartOfSwiftCompilation)
      let path = RelativePath(createTemporaryFileName(prefix: "sources"))
      self.allSourcesFileList = .fileList(path, .list(swiftInputs.map(\.file)))
    } else {
      self.allSourcesFileList = nil
    }

    self.lto = Self.ltoKind(&parsedOptions, diagnosticsEngine: diagnosticsEngine)
    // Figure out the primary outputs from the driver.
    (self.compilerOutputType, self.linkerOutputType) = Self.determinePrimaryOutputs(&parsedOptions, driverKind: driverKind, diagnosticsEngine: diagnosticEngine)

    // Multithreading.
    self.numThreads = Self.determineNumThreads(&parsedOptions, compilerMode: compilerMode, diagnosticsEngine: diagnosticEngine)
    self.numParallelJobs = Self.determineNumParallelJobs(&parsedOptions, diagnosticsEngine: diagnosticEngine, env: env)

    Self.validateWarningControlArgs(&parsedOptions, diagnosticEngine: diagnosticEngine)
    Self.validateCRuntimeArgs(&parsedOptions,
                              diagnosticEngine: diagnosticsEngine,
                              targetTriple: self.frontendTargetInfo.target.triple)
    Self.validateProfilingArgs(&parsedOptions,
                               fileSystem: fileSystem,
                               workingDirectory: workingDirectory,
                               diagnosticEngine: diagnosticEngine)
    Self.validateCompilationConditionArgs(&parsedOptions, diagnosticEngine: diagnosticEngine)
    Self.validateFrameworkSearchPathArgs(&parsedOptions, diagnosticEngine: diagnosticEngine)
    Self.validateCoverageArgs(&parsedOptions, diagnosticsEngine: diagnosticEngine)
    try toolchain.validateArgs(&parsedOptions,
                               targetTriple: self.frontendTargetInfo.target.triple,
                               targetVariantTriple: self.frontendTargetInfo.targetVariant?.triple,
                               diagnosticsEngine: diagnosticEngine)

    // Compute debug information output.
    self.debugInfo = Self.computeDebugInfo(&parsedOptions, diagnosticsEngine: diagnosticEngine)

    // Determine the module we're building and whether/how the module file itself will be emitted.
    self.moduleOutputInfo = try Self.computeModuleInfo(
      &parsedOptions, compilerOutputType: compilerOutputType, compilerMode: compilerMode, linkerOutputType: linkerOutputType,
      debugInfoLevel: debugInfo.level, diagnosticsEngine: diagnosticEngine,
      workingDirectory: self.workingDirectory)

    self.buildRecordInfo = BuildRecordInfo(
      actualSwiftVersion: self.frontendTargetInfo.compilerVersion,
      compilerOutputType: compilerOutputType,
      workingDirectory: self.workingDirectory ?? fileSystem.currentWorkingDirectory,
      diagnosticEngine: diagnosticEngine,
      fileSystem: fileSystem,
      moduleOutputInfo: moduleOutputInfo,
      outputFileMap: outputFileMap,
      parsedOptions: parsedOptions,
      recordedInputModificationDates: recordedInputModificationDates)

    self.importedObjCHeader = try Self.computeImportedObjCHeader(&parsedOptions, compilerMode: compilerMode, diagnosticEngine: diagnosticEngine)
    self.bridgingPrecompiledHeader = try Self.computeBridgingPrecompiledHeader(&parsedOptions,
                                                                               compilerMode: compilerMode,
                                                                               importedObjCHeader: importedObjCHeader,
                                                                               outputFileMap: outputFileMap)

    self.supportedFrontendFlags =
      try Self.computeSupportedCompilerFeatures(of: self.toolchain, hostTriple: self.hostTriple,
                                                parsedOptions: &self.parsedOptions,
                                                diagnosticsEngine: diagnosticEngine,
                                                fileSystem: fileSystem, executor: executor,
                                                env: env)

    self.enabledSanitizers = try Self.parseSanitizerArgValues(
      &parsedOptions,
      diagnosticEngine: diagnosticEngine,
      toolchain: toolchain,
      targetInfo: frontendTargetInfo)

    Self.validateSanitizerCoverageArgs(&parsedOptions,
                                       anySanitizersEnabled: !enabledSanitizers.isEmpty,
                                       diagnosticsEngine: diagnosticsEngine)

    // Supplemental outputs.
    self.dependenciesFilePath = try Self.computeSupplementaryOutputPath(
        &parsedOptions, type: .dependencies, isOutputOptions: [.emitDependencies],
        outputPath: .emitDependenciesPath,
        compilerOutputType: compilerOutputType,
        compilerMode: compilerMode,
        outputFileMap: self.outputFileMap,
        moduleName: moduleOutputInfo.name)
    self.referenceDependenciesPath = try Self.computeSupplementaryOutputPath(
        &parsedOptions, type: .swiftDeps, isOutputOptions: shouldAttemptIncrementalCompilation ? [.incremental] : [],
        outputPath: .emitReferenceDependenciesPath,
        compilerOutputType: compilerOutputType,
        compilerMode: compilerMode,
        outputFileMap: self.outputFileMap,
        moduleName: moduleOutputInfo.name)
    self.serializedDiagnosticsFilePath = try Self.computeSupplementaryOutputPath(
        &parsedOptions, type: .diagnostics, isOutputOptions: [.serializeDiagnostics],
        outputPath: .serializeDiagnosticsPath,
        compilerOutputType: compilerOutputType,
        compilerMode: compilerMode,
        outputFileMap: self.outputFileMap,
        moduleName: moduleOutputInfo.name)
    // FIXME: -fixits-output-path
    self.objcGeneratedHeaderPath = try Self.computeSupplementaryOutputPath(
        &parsedOptions, type: .objcHeader, isOutputOptions: [.emitObjcHeader],
        outputPath: .emitObjcHeaderPath,
        compilerOutputType: compilerOutputType,
        compilerMode: compilerMode,
        outputFileMap: self.outputFileMap,
        moduleName: moduleOutputInfo.name)

    if let loadedModuleTraceEnvVar = env["SWIFT_LOADED_MODULE_TRACE_FILE"] {
      self.loadedModuleTracePath = try VirtualPath(path: loadedModuleTraceEnvVar)
    } else {
      self.loadedModuleTracePath = try Self.computeSupplementaryOutputPath(
        &parsedOptions, type: .moduleTrace, isOutputOptions: [.emitLoadedModuleTrace],
        outputPath: .emitLoadedModuleTracePath,
        compilerOutputType: compilerOutputType,
        compilerMode: compilerMode,
        outputFileMap: self.outputFileMap,
        moduleName: moduleOutputInfo.name)
    }

    self.tbdPath = try Self.computeSupplementaryOutputPath(
        &parsedOptions, type: .tbd, isOutputOptions: [.emitTbd],
        outputPath: .emitTbdPath,
        compilerOutputType: compilerOutputType,
        compilerMode: compilerMode,
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
    self.swiftInterfacePath = try Self.computeSupplementaryOutputPath(
        &parsedOptions, type: .swiftInterface, isOutputOptions: [.emitModuleInterface],
        outputPath: .emitModuleInterfacePath,
        compilerOutputType: compilerOutputType,
        compilerMode: compilerMode,
        outputFileMap: self.outputFileMap,
        moduleName: moduleOutputInfo.name)

    self.swiftPrivateInterfacePath = try Self.computeSupplementaryOutputPath(
        &parsedOptions, type: .privateSwiftInterface, isOutputOptions: [],
        outputPath: .emitPrivateModuleInterfacePath,
        compilerOutputType: compilerOutputType,
        compilerMode: compilerMode,
        outputFileMap: self.outputFileMap,
        moduleName: moduleOutputInfo.name)

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
    self.optimizationRecordPath = try Self.computeSupplementaryOutputPath(
        &parsedOptions, type: optimizationRecordFileType,
        isOutputOptions: [.saveOptimizationRecord, .saveOptimizationRecordEQ],
        outputPath: .saveOptimizationRecordPath,
        compilerOutputType: compilerOutputType,
        compilerMode: compilerMode,
        outputFileMap: self.outputFileMap,
        moduleName: moduleOutputInfo.name)
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
    guard execName == "swift" || execName == "swiftc", args.count > 1 else {
      return (.normal(isRepl: false), args)
    }

    // Otherwise, we have a program argument.
    let firstArg = args[1]
    var updatedArgs = args

    // Check for flags associated with frontend tools.
    if firstArg == "-frontend" {
      updatedArgs.replaceSubrange(0...1, with: ["swift-frontend"])
      return (.subcommand("swift-frontend"), updatedArgs)
    }

    if firstArg == "-modulewrap" {
      updatedArgs[0] = "swift-frontend"
      return (.subcommand("swift-frontend"), updatedArgs)
    }

    // Only 'swift' supports subcommands.
    guard execName == "swift" else {
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
        return (.normal(isRepl: true), updatedArgs)
    }

    let subcommand = "swift-\(firstArg)"

    updatedArgs.replaceSubrange(0...1, with: [subcommand])

    return (.subcommand(subcommand), updatedArgs)
  }
}

extension Driver {
  private static func ltoKind(_ parsedOptions: inout ParsedOptions,
                              diagnosticsEngine: DiagnosticsEngine) -> LTOKind? {
    guard let arg = parsedOptions.getLastArgument(.lto)?.asSingle else { return nil }
    guard let kind = LTOKind(rawValue: arg) else {
      diagnosticsEngine.emit(.error_invalid_arg_value(arg: .lto, value: arg))
      return nil
    }
    return kind
  }
}

// MARK: - Response files.
extension Driver {
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

  /// Tokenize each line of the response file, omitting empty lines.
  ///
  /// - Parameter content: response file's content to be tokenized.
  private static func tokenizeResponseFile(_ content: String) -> [String] {
    #if !os(macOS) && !os(Linux) && !os(Android) && !os(Windows)
      #warning("Response file tokenization unimplemented for platform; behavior may be incorrect")
    #endif
    return content.split { $0 == "\n" || $0 == "\r\n" }
           .flatMap { tokenizeResponseFileLine($0) }
  }

  /// Recursively expands the response files.
  /// - Parameter visitedResponseFiles: Set containing visited response files to detect recursive parsing.
  private static func expandResponseFiles(
    _ args: [String],
    fileSystem: FileSystem,
    diagnosticsEngine: DiagnosticsEngine,
    visitedResponseFiles: inout Set<AbsolutePath>
  ) throws -> [String] {
    var result: [String] = []

    // Go through each arg and add arguments from response files.
    for arg in args {
      if arg.first == "@", let responseFile = try? AbsolutePath(validating: String(arg.dropFirst())) {
        // Guard against infinite parsing loop.
        guard visitedResponseFiles.insert(responseFile).inserted else {
          diagnosticsEngine.emit(.warn_recursive_response_file(responseFile))
          continue
        }
        defer {
          visitedResponseFiles.remove(responseFile)
        }

        let contents = try fileSystem.readFileContents(responseFile).cString
        let lines = tokenizeResponseFile(contents)
        result.append(contentsOf: try expandResponseFiles(lines, fileSystem: fileSystem, diagnosticsEngine: diagnosticsEngine, visitedResponseFiles: &visitedResponseFiles))
      } else {
        result.append(arg)
      }
    }

    return result
  }

  /// Expand response files in the input arguments and return a new argument list.
  @_spi(Testing) public static func expandResponseFiles(
    _ args: [String],
    fileSystem: FileSystem,
    diagnosticsEngine: DiagnosticsEngine
  ) throws -> [String] {
    var visitedResponseFiles = Set<AbsolutePath>()
    return try expandResponseFiles(args, fileSystem: fileSystem, diagnosticsEngine: diagnosticsEngine, visitedResponseFiles: &visitedResponseFiles)
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

    // Determine if the driver kind is being overriden.
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

    if parsedOptions.contains(.driverPrintOutputFileMap) {
      if let outputFileMap = self.outputFileMap {
        stderrStream <<< outputFileMap.description
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
          self.incrementalCompilationState?.writeDependencyGraph()
          buildRecordInfo?.writeBuildRecord(
            jobs,
            incrementalCompilationState?.skippedCompilationInputs)
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
        stderrStream <<< "swift-driver version: " <<< Driver.driverSourceVersion <<< " "
        stderrStream.flush()
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

    // FIXME: Old driver does _something_ if both are passed. Not sure if we want to support that.
    if parsedOptions.contains(.parseableOutput) {
      mode = .parsableOutput
    } else if parsedOptions.contains(.v) {
      mode = .verbose
    }

    return ToolExecutionDelegate(
      mode: mode,
      buildRecordInfo: buildRecordInfo,
      incrementalCompilationState: incrementalCompilationState,
      showJobLifecycle: showJobLifecycle,
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
                      continueBuildingAfterErrors: continueBuildingAfterErrors),
      delegate: jobExecutionDelegate,
      numParallelJobs: numParallelJobs ?? 1,
      forceResponseFiles: forceResponseFiles,
      recordedInputModificationDates: recordedInputModificationDates)
  }

  private func printBindings(_ job: Job) {
    stdoutStream <<< #"# ""# <<< targetTriple.triple
    stdoutStream <<< #"" - ""# <<< job.tool.basename
    stdoutStream <<< #"", inputs: ["#
    stdoutStream <<< job.displayInputs.map { "\"" + $0.file.name + "\"" }.joined(separator: ", ")

    stdoutStream <<< "], output: {"

    stdoutStream <<< job.outputs.map { $0.type.name + ": \"" + $0.file.name + "\"" }.joined(separator: ", ")

    stdoutStream <<< "}"
    stdoutStream <<< "\n"
    stdoutStream.flush()
  }

  /// This handles -driver-print-actions flag. The C++ driver has a concept of actions
  /// which it builds up a list of actions before then creating them into jobs.
  /// The swift-driver doesn't have actions, so the logic here takes the jobs and tries
  /// to mimic the actions that would be created by the C++ driver and
  /// prints them in *hopefully* the same order.
  private func printActions(_ jobs: [Job]) {
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
      // Collect input job IDs.
      for input in job.displayInputs.isEmpty ? job.inputs : job.displayInputs {
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
      stdoutStream <<< nextId <<< ": " <<< job.kind.rawValue <<< ", {"
      switch job.kind {
      // Don't sort for compile jobs. Puts pch last
      case .compile:
        stdoutStream <<< inputIds.map(\.description).joined(separator: ", ")
      default:
        stdoutStream <<< inputIds.sorted().map(\.description).joined(separator: ", ")
      }
      var typeName = job.outputs.first?.type.name
      if typeName == nil {
        typeName = "none"
      }
      stdoutStream <<< "}, " <<< typeName! <<< "\n"
      jobIdMap[job] = nextId
      nextId += 1
    }
  }

  private static func printInputIfNew(_ input: TypedVirtualPath, inputIdMap: inout [TypedVirtualPath: UInt], nextId: inout UInt) {
    if inputIdMap[input] == nil {
      stdoutStream <<< nextId <<< ": " <<< "input, "
      stdoutStream <<< "\"" <<< input.file <<< "\", " <<< input.type <<< "\n"
      inputIdMap[input] = nextId
      nextId += 1
    }
  }

  private func printVersion<S: OutputByteStream>(outputStream: inout S) throws {
    outputStream <<< frontendTargetInfo.compilerVersion <<< "\n"
    outputStream <<< "Target: \(frontendTargetInfo.target.triple.triple)\n"
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

      case .repl:
        if driverKind == .interactive, !parsedOptions.hasAnyInput {
          diagnosticsEngine.emit(.warning_unnecessary_repl_mode(option: outputOption.option, kind: driverKind))
        }
        fallthrough
      case .lldbRepl:
        return .repl

      case .deprecatedIntegratedRepl:
        throw Error.integratedReplRemoved

      case .emitPcm:
        return .compilePCM

      default:
        // Output flag doesn't determine the compiler mode.
        break
      }
    }

    if driverKind == .interactive {
      return parsedOptions.hasAnyInput ? .immediate : .repl
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
  static func warning_unnecessary_repl_mode(option: Option, kind: DriverKind) -> Diagnostic.Message {
    .warning("unnecessary option '\(option.spelling)'; this is the default for '\(kind.rawValue)' with no input files")
  }

  static func warn_ignoring_batch_mode(_ option: Option) -> Diagnostic.Message {
    .warning("ignoring '-enable-batch-mode' because '\(option.spelling)' was also specified")
  }
}

/// Input and output file handling.
extension Driver {
  /// Apply the given working directory to all paths in the parsed options.
  private static func applyWorkingDirectory(_ workingDirectory: AbsolutePath,
                                            to parsedOptions: inout ParsedOptions) throws {
    parsedOptions.forEachModifying { parsedOption in
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
          translatedArgument = .single(AbsolutePath(arg, relativeTo: workingDirectory).pathString)
        }

      case .multiple(let args):
        translatedArgument = .multiple(args.map { arg in
          AbsolutePath(arg, relativeTo: workingDirectory).pathString
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
  private static func collectInputFiles(_ parsedOptions: inout ParsedOptions, diagnosticsEngine: DiagnosticsEngine) throws -> [TypedVirtualPath] {
    var swiftFiles = [String: String]() // [Basename: Path]
    return try parsedOptions.allInputs.map { input in
      // Standard input is assumed to be Swift code.
      if input == "-" {
        return TypedVirtualPath(file: .standardInput, type: .swift)
      }

      // Resolve the input file.
      let file = try VirtualPath(path: input)
      let fileExtension = file.extension ?? ""

      // Determine the type of the input file based on its extension.
      // If we don't recognize the extension, treat it as an object file.
      // FIXME: The object-file default is carried over from the existing
      // driver, but seems odd.
      let fileType = FileType(rawValue: fileExtension) ?? FileType.object
      
      if fileType == .swift {
        let basename = file.basename
        if let originalPath = swiftFiles[basename] {
          diagnosticsEngine.emit(.error_two_files_same_name(basename: basename, firstPath: originalPath, secondPath: input))
          diagnosticsEngine.emit(.note_explain_two_files_same_name)
          throw Diagnostics.fatalError
        } else {
          swiftFiles[basename] = input
        }
      }

      return TypedVirtualPath(file: file, type: fileType)
    }
  }

  /// Determine the primary compiler and linker output kinds.
  private static func determinePrimaryOutputs(
    _ parsedOptions: inout ParsedOptions,
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
        if parsedOptions.contains(.static) {
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

      case .emitIr:
        compilerOutputType = .llvmIR

      case .emitBc:
        compilerOutputType = .llvmBitcode

      case .dumpAst:
        compilerOutputType = .ast

      case .emitPcm:
        compilerOutputType = .pcm

      case .emitImportedModules:
        compilerOutputType = .importedModules

      case .indexFile:
        compilerOutputType = .indexData

      case .parse, .resolveImports, .typecheck, .dumpParse, .emitSyntax,
           .printAst, .dumpTypeRefinementContexts, .dumpScopeMaps,
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
  private static func computeDebugInfo(_ parsedOptions: inout ParsedOptions, diagnosticsEngine: DiagnosticsEngine) -> DebugInfo {
    var shouldVerify = parsedOptions.hasArgument(.verifyDebugInfo)

    for debugPrefixMap in parsedOptions.arguments(for: .debugPrefixMap) {
      let value = debugPrefixMap.argument.asSingle
      let parts = value.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      if parts.count != 2 {
        diagnosticsEngine.emit(.error_opt_invalid_mapping(option: debugPrefixMap.option, value: value))
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

    return DebugInfo(format: format, level: level, shouldVerify: shouldVerify)
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

      // Support is determined by existence of the sanitizer library.
      // FIXME: Should we do this? This prevents cross-compiling with sanitizers
      //        enabled.
      var sanitizerSupported = try toolchain.runtimeLibraryExists(
        for: sanitizer,
        targetInfo: targetInfo,
        parsedOptions: &parsedOptions,
        isShared: sanitizer != .fuzzer
      )

      // TSan is explicitly not supported for 32 bits.
      if sanitizer == .thread && !targetTriple.arch!.is64Bit {
        sanitizerSupported = false
      }

      // Currently only ASAN is supported on Windows.
      if sanitizer != .address && targetTriple.isWindows {
        sanitizerSupported = false
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

  /// Whether we are going to be building an executable.
  ///
  /// FIXME: Why "maybe"? Why isn't this all known in advance as captured in
  /// linkerOutputType?
  private static func maybeBuildingExecutable(
    _ parsedOptions: inout ParsedOptions,
    linkerOutputType: LinkOutputType?
  ) -> Bool {
    switch linkerOutputType {
    case .executable:
      return true

    case .dynamicLibrary, .staticLibrary:
      return false

    default:
      break
    }

    if parsedOptions.hasArgument(.parseAsLibrary, .parseStdlib) {
      return false
    }

    return parsedOptions.allInputs.count == 1
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
    } else if compilerMode != .singleCompile &&
      parsedOptions.hasArgument(.emitObjcHeader, .emitObjcHeaderPath,
                                .emitModuleInterface, .emitModuleInterfacePath,
                                .emitPrivateModuleInterfacePath) {
      // An option has been passed which requires whole-module knowledge, but we
      // don't have that. Generate a module, but treat it as an intermediate
      // output.
      moduleOutputKind = .auxiliary
    } else {
      // No options require a module, so don't generate one.
      moduleOutputKind = nil
    }

    // The REPL and immediate mode do not support module output
    if moduleOutputKind != nil && (compilerMode == .repl || compilerMode == .immediate) {
      diagnosticsEngine.emit(.error_mode_cannot_emit_module)
      moduleOutputKind = nil
    }

    // Determine the name of the module.
    var moduleName: String
    var moduleNameIsFallback = false
    if let arg = parsedOptions.getLastArgument(.moduleName) {
      moduleName = arg.asSingle
    } else if compilerMode == .repl {
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
      if compilerOutputType == nil || maybeBuildingExecutable(&parsedOptions, linkerOutputType: linkerOutputType) {
        moduleName = "main"
      }
      else {
        diagnosticsEngine.emit(error)
        moduleName = "__bad__"
      }
    }

    if !moduleName.sd_isSwiftIdentifier {
      fallbackOrDiagnose(.error_bad_module_name(moduleName: moduleName, explicitModuleName: parsedOptions.contains(.moduleName)))
    } else if moduleName == "Swift" && !parsedOptions.contains(.parseStdlib) {
      fallbackOrDiagnose(.error_stdlib_module_name(moduleName: moduleName, explicitModuleName: parsedOptions.contains(.moduleName)))
    }

    // If we're not emiting a module, we're done.
    if moduleOutputKind == nil {
      return ModuleOutputInfo(output: nil, name: moduleName, nameIsFallback: moduleNameIsFallback)
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
      moduleOutputPath = .temporary(RelativePath(moduleName.appendingFileTypeExtension(.swiftModule)))
    }

    // Use working directory if specified
    if let moduleRelative = moduleOutputPath.relativePath {
      moduleOutputPath = Driver.useWorkingDirectory(moduleRelative, workingDirectory)
    }

    switch moduleOutputKind! {
    case .topLevel:
      return ModuleOutputInfo(output: .topLevel(moduleOutputPath), name: moduleName, nameIsFallback: moduleNameIsFallback)
    case .auxiliary:
      return ModuleOutputInfo(output: .auxiliary(moduleOutputPath), name: moduleName, nameIsFallback: moduleNameIsFallback)
    }
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
    sdkPath = sdkPath.map { $0.last == "/" ? String($0.dropLast()) : $0 }

    // Validate the SDK if we found one.
    if let sdkPath = sdkPath {
      let path: AbsolutePath

      // FIXME: TSC should provide a better utility for this.
      if let absPath = try? AbsolutePath(validating: sdkPath) {
        path = absPath
      } else if let cwd = fileSystem.currentWorkingDirectory {
        path = AbsolutePath(sdkPath, relativeTo: cwd)
      } else {
        diagnosticsEngine.emit(.warning_no_such_sdk(sdkPath))
        return nil
      }

      if !fileSystem.exists(path) {
        diagnosticsEngine.emit(.warning_no_such_sdk(sdkPath))
      }
      // .. else check if SDK is too old (we need target triple to diagnose that).

      return .absolute(path)
    }

    return nil
  }
}

// Imported Objective-C header.
extension Driver {
  /// Compute the path of the imported Objective-C header.
  static func computeImportedObjCHeader(_ parsedOptions: inout ParsedOptions, compilerMode: CompilerMode, diagnosticEngine: DiagnosticsEngine) throws -> VirtualPath? {
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

    return try VirtualPath(path: objcHeaderPathArg.asSingle)
  }

  /// Compute the path of the generated bridging PCH for the Objective-C header.
  static func computeBridgingPrecompiledHeader(_ parsedOptions: inout ParsedOptions,
                                               compilerMode: CompilerMode,
                                               importedObjCHeader: VirtualPath?,
                                               outputFileMap: OutputFileMap?) throws -> VirtualPath? {
    guard compilerMode.supportsBridgingPCH,
      let input = importedObjCHeader,
      parsedOptions.hasFlag(positive: .enableBridgingPch, negative: .disableBridgingPch, default: true) else {
        return nil
    }

    if let outputPath = outputFileMap?.existingOutput(inputFile: input, outputType: .pch) {
      return outputPath
    }

    // FIXME: should have '-.*' at the end of the filename, similar to llvm::sys::fs::createTemporaryFile
    let pchFileName = input.basenameWithoutExt.appendingFileTypeExtension(.pch)
    if let outputDirectory = parsedOptions.getLastArgument(.pchOutputDir)?.asSingle {
      return try VirtualPath(path: outputDirectory).appending(component: pchFileName)
    } else {
      return .temporary(RelativePath(pchFileName))
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
      diagnosticEngine.emit(Error.conflictingOptions(.warningsAsErrors, .suppressWarnings))
    }
  }

  static func validateCRuntimeArgs(_ parsedOptions: inout ParsedOptions,
                                   diagnosticEngine: DiagnosticsEngine,
                                   targetTriple: Triple) {
    if parsedOptions.hasArgument(.libc) && !targetTriple.isWindows {
      diagnosticEngine.emit(.error_unsupported_opt_for_target(arg: "-libc", target: targetTriple))
    }
  }

  static func validateProfilingArgs(_ parsedOptions: inout ParsedOptions,
                                    fileSystem: FileSystem,
                                    workingDirectory: AbsolutePath?,
                                    diagnosticEngine: DiagnosticsEngine) {
    if parsedOptions.hasArgument(.profileGenerate) &&
        parsedOptions.hasArgument(.profileUse) {
      diagnosticEngine.emit(Error.conflictingOptions(.profileGenerate, .profileUse))
    }

    if let profileArgs = parsedOptions.getLastArgument(.profileUse)?.asMultiple,
       let workingDirectory = workingDirectory ?? fileSystem.currentWorkingDirectory {
      for profilingData in profileArgs {
        if !fileSystem.exists(AbsolutePath(profilingData,
                                           relativeTo: workingDirectory)) {
          diagnosticEngine.emit(Error.missingProfilingData(profilingData))
        }
      }
    }
  }

  static func validateCompilationConditionArgs(_ parsedOptions: inout ParsedOptions,
                                               diagnosticEngine: DiagnosticsEngine) {
    for arg in parsedOptions.arguments(for: .D).map(\.argument.asSingle) {
      if arg.contains("=") {
        diagnosticEngine.emit(.warning_cannot_assign_to_compilation_condition(name: arg))
      } else if arg.hasPrefix("-D") {
        diagnosticEngine.emit(Error.conditionalCompilationFlagHasRedundantPrefix(arg))
      } else if !arg.sd_isSwiftIdentifier {
        diagnosticEngine.emit(Error.conditionalCompilationFlagIsNotValidIdentifier(arg))
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
  func toolchainType(_ diagnosticsEngine: DiagnosticsEngine) throws -> Toolchain.Type {
    switch os {
    case .darwin, .macosx, .ios, .tvos, .watchos:
      return DarwinToolchain.self
    case .linux:
      return GenericUnixToolchain.self
    case .freeBSD, .haiku:
      return GenericUnixToolchain.self
    case .wasi:
      return WebAssemblyToolchain.self
    case .win32:
      return WindowsToolchain.self
    default:
      diagnosticsEngine.emit(.error_unknown_target(triple))
      throw Diagnostics.fatalError
    }
  }
}

/// Toolchain computation.
extension Driver {
  #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
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
    swiftCompilerPrefixArgs: [String]) throws -> Triple {

    let frontendOverride = try FrontendOverride(&parsedOptions, diagnosticsEngine)
    frontendOverride.setUpForTargetInfo(toolchain)
    defer { frontendOverride.setUpForCompilation(toolchain) }
    return try executor.execute(
      job: toolchain.printTargetInfoJob(target: nil, targetVariant: nil,
                                        swiftCompilerPrefixArgs:
                                          frontendOverride.prefixArgsForTargetInfo),
      capturingJSONOutputAs: FrontendTargetInfo.self,
      forceResponseFiles: false,
      recordedInputModificationDates: [:]).target.triple
  }

  static func computeToolchain(
    _ parsedOptions: inout ParsedOptions,
    diagnosticsEngine: DiagnosticsEngine,
    compilerMode: CompilerMode,
    env: [String: String],
    executor: DriverExecutor,
    fileSystem: FileSystem,
    useStaticResourceDir: Bool,
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
      var info: FrontendTargetInfo = try executor.execute(
        job: toolchain.printTargetInfoJob(
          target: explicitTarget, targetVariant: explicitTargetVariant,
          sdkPath: sdkPath, resourceDirPath: resourceDirPath,
          runtimeCompatibilityVersion:
            parsedOptions.getLastArgument(.runtimeCompatibilityVersion)?.asSingle,
          useStaticResourceDir: useStaticResourceDir,
          swiftCompilerPrefixArgs: frontendOverride.prefixArgsForTargetInfo
        ),
        capturingJSONOutputAs: FrontendTargetInfo.self,
        forceResponseFiles: false,
        recordedInputModificationDates: [:])

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
      return overridePath?.basename != "Python"
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
    outputFileMap: OutputFileMap?,
    moduleName: String
  ) throws -> VirtualPath? {
    // If there is an explicit argument for the output path, use that
    if let outputPathArg = parsedOptions.getLastArgument(outputPath) {
      for isOutput in isOutputOptions {
        // Consume the isOutput argument
        _ = parsedOptions.hasArgument(isOutput)
      }
      return try VirtualPath(path: outputPathArg.asSingle)
    }

    // If no output option was provided, don't produce this output at all.
    guard isOutputOptions.contains(where: { parsedOptions.hasArgument($0) }) else {
      return nil
    }

    // If this is a single-file compile and there is an entry in the
    // output file map, use that.
    if compilerMode.isSingleCompilation,
        let singleOutputPath = outputFileMap?.existingOutputForSingleInput(
            outputType: type) {
      return singleOutputPath
    }

    // If there is an output argument, derive the name from there.
    if let outputPathArg = parsedOptions.getLastArgument(.o) {
      let path = try VirtualPath(path: outputPathArg.asSingle)

      // If the compiler output is of this type, use the argument directly.
      if type == compilerOutputType {
        return path
      }

      return path.parentDirectory.appending(component: "\(moduleName).\(type.rawValue)")
    }

    return try VirtualPath(path: moduleName.appendingFileTypeExtension(type))
  }

  /// Determine if the build system has created a Project/ directory for auxilary outputs.
  static func computeProjectDirectoryPath(moduleOutputPath: VirtualPath?,
                                          fileSystem: FileSystem) -> VirtualPath? {
    let potentialProjectDirectory = moduleOutputPath?
      .parentDirectory
      .appending(component: "Project")
      .absolutePath
    guard let projectDirectory = potentialProjectDirectory, fileSystem.exists(projectDirectory) else {
      return nil
    }
    return .absolute(projectDirectory)
  }

  /// Determine the output path for a module documentation.
  static func computeModuleDocOutputPath(
    _ parsedOptions: inout ParsedOptions,
    moduleOutputPath: VirtualPath?,
    compilerOutputType: FileType?,
    compilerMode: CompilerMode,
    outputFileMap: OutputFileMap?,
    moduleName: String
  ) throws -> VirtualPath? {
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
    moduleOutputPath: VirtualPath?,
    compilerOutputType: FileType?,
    compilerMode: CompilerMode,
    outputFileMap: OutputFileMap?,
    moduleName: String,
    projectDirectory: VirtualPath?
  ) throws -> VirtualPath? {
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


  /// Determine the output path for a module auxiliary output.
  static func computeModuleAuxiliaryOutputPath(
    _ parsedOptions: inout ParsedOptions,
    moduleOutputPath: VirtualPath?,
    type: FileType,
    isOutput: Option?,
    outputPath: Option,
    compilerOutputType: FileType?,
    compilerMode: CompilerMode,
    outputFileMap: OutputFileMap?,
    moduleName: String,
    projectDirectory: VirtualPath? = nil
  ) throws -> VirtualPath? {
    // If there is an explicit argument for the output path, use that
    if let outputPathArg = parsedOptions.getLastArgument(outputPath) {
      // Consume the isOutput argument
      if let isOutput = isOutput {
        _ = parsedOptions.hasArgument(isOutput)
      }
      return try VirtualPath(path: outputPathArg.asSingle)
    }

    // If this is a single-file compile and there is an entry in the
    // output file map, use that.
    if compilerMode.isSingleCompilation,
        let singleOutputPath = outputFileMap?.existingOutputForSingleInput(
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
        parentPath = projectDirectory
      } else {
        parentPath = moduleOutputPath.parentDirectory
      }

      return parentPath.appending(component: moduleOutputPath.basename).replacingExtension(with: type)
    }

    // If the output option was not provided, don't produce this output at all.
    guard let isOutput = isOutput, parsedOptions.hasArgument(isOutput) else {
      return nil
    }

    return try VirtualPath(path: moduleName.appendingFileTypeExtension(type))
  }
}
