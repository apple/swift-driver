//===--------------- Planning.swift - Swift Compilation Planning ----------===//
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

public enum PlanningError: Error, DiagnosticData {
  case replReceivedInput
  case emitPCMWrongInputFiles

  public var description: String {
    switch self {
    case .replReceivedInput:
      return "REPL mode requires no input files"

    case .emitPCMWrongInputFiles:
      return "Clang module emission requires exactly one input file (the module map)"
    }
  }
}

/// When emitting bitcode, if the first compile job is scheduled, the second must be.
/// So, group them together for incremental build purposes.
struct CompileJobGroup {
  let compileJob: Job
  let backendJob: Job?

  init(compileJob: Job, backendJob: Job?) {
    assert(compileJob.kind == .compile)
    assert(compileJob.primaryInputs.count == 1, "must be unbatched")
    assert(backendJob?.kind ?? .backend == .backend)
    self.compileJob = compileJob
    self.backendJob = backendJob
  }

  func allJobs() -> [Job] {
    backendJob.map {[compileJob, $0]} ?? [compileJob]
  }

  var primaryInput: TypedVirtualPath {
    compileJob.primaryInputs[0]
  }

  var outputs: [TypedVirtualPath] {
    allJobs().flatMap {$0.outputs}
  }
}

@_spi(Testing) public struct JobsInPhases {
  /// In WMO mode, also includes the multi-compile & its backends, since there are >1 backend jobs
  let beforeCompiles: [Job]
  let compileGroups: [CompileJobGroup]
  let afterCompiles: [Job]

  var allJobs: [Job] {
    var r = beforeCompiles
    compileGroups.forEach { r.append(contentsOf: $0.allJobs()) }
    r.append(contentsOf: afterCompiles)
    return r
  }

  @_spi(Testing) public static var none = JobsInPhases(beforeCompiles: [],
                                 compileGroups: [],
                                 afterCompiles: [])
}

// MARK: Standard build planning
extension Driver {
  /// Plan a standard compilation, which produces jobs for compiling separate
  /// primary files.
  private mutating func planStandardCompile() throws
  -> ([Job], IncrementalCompilationState?) {
    precondition(compilerMode.isStandardCompilationForPlanning,
                 "compiler mode \(compilerMode) is handled elsewhere")

    // Centralize job accumulation here.
    // For incremental compilation, must separate jobs happening before,
    // during, and after compilation.
    var jobsBeforeCompiles = [Job]()
    func addJobBeforeCompiles(_ job: Job) {
      assert(job.kind != .compile || job.primaryInputs.isEmpty)
      jobsBeforeCompiles.append(job)
    }

    var compileJobGroups = [CompileJobGroup]()
    func addCompileJobGroup(_ group: CompileJobGroup) {
      compileJobGroups.append(group)
    }

    // need to buffer these to dodge shared ownership
    var jobsAfterCompiles = [Job]()
    func addJobAfterCompiles(_ j: Job) {
      jobsAfterCompiles.append(j)
    }

    try addPrecompileModuleDependenciesJobs(addJob: addJobBeforeCompiles)
    try addPrecompileBridgingHeaderJob(addJob: addJobBeforeCompiles)
    try addEmitModuleJob(addJob: addJobBeforeCompiles)
    let linkerInputs = try addJobsFeedingLinker(
      addJobBeforeCompiles: addJobBeforeCompiles,
      addCompileJobGroup: addCompileJobGroup,
      addJobAfterCompiles: addJobAfterCompiles)
    try addLinkAndPostLinkJobs(linkerInputs: linkerInputs,
                               debugInfo: debugInfo,
                               addJob: addJobAfterCompiles)

    let jobsInPhases = JobsInPhases(
      beforeCompiles: jobsBeforeCompiles,
      compileGroups: compileJobGroups,
      afterCompiles: jobsAfterCompiles
    )

    // Determine the state for incremental compilation
    let incrementalCompilationState = try IncrementalCompilationState(
      driver: &self,
      options: self.computeIncrementalOptions(),
      jobsInPhases: jobsInPhases)

    return try (
      // For compatibility with swiftpm, the driver produces batched jobs
      // for every job, even when run in incremental mode, so that all jobs
      // can be returned from `planBuild`.
      // But in that case, don't emit lifecycle messages.
      formBatchedJobs(jobsInPhases.allJobs,
                      showJobLifecycle: showJobLifecycle && incrementalCompilationState == nil),
      incrementalCompilationState
    )
  }

  mutating func computeIncrementalOptions() -> IncrementalCompilationState.Options {
    var options: IncrementalCompilationState.Options = []
    if self.parsedOptions.contains(.driverAlwaysRebuildDependents) {
      options.formUnion(.alwaysRebuildDependents)
    }
    if self.parsedOptions.contains(.driverShowIncremental) || self.showJobLifecycle {
      options.formUnion(.showIncremental)
    }
    let emitOpt = Option.driverEmitFineGrainedDependencyDotFileAfterEveryImport
    if self.parsedOptions.contains(emitOpt) {
      options.formUnion(.emitDependencyDotFileAfterEveryImport)
    }
    let veriOpt = Option.driverVerifyFineGrainedDependencyGraphAfterEveryImport
    if self.parsedOptions.contains(veriOpt) {
      options.formUnion(.verifyDependencyGraphAfterEveryImport)
    }
    if self.parsedOptions.contains(.enableExperimentalCrossModuleIncrementalBuild) {
      options.formUnion(.enableCrossModuleIncrementalBuild)
      options.formUnion(.readPriorsFromModuleDependencyGraph)
    }
    return options
  }

  private mutating func addPrecompileModuleDependenciesJobs(addJob: (Job) -> Void) throws {
    // If asked, add jobs to precompile module dependencies
    guard parsedOptions.contains(.driverExplicitModuleBuild) else { return }
    let modulePrebuildJobs = try generateExplicitModuleDependenciesJobs()
    modulePrebuildJobs.forEach(addJob)
  }


  private mutating func addPrecompileBridgingHeaderJob(addJob: (Job) -> Void) throws {
    guard
      let importedObjCHeader = importedObjCHeader,
      let bridgingPrecompiledHeader = bridgingPrecompiledHeader
    else { return }

    addJob(
      try generatePCHJob(input:  .init(file: importedObjCHeader,
                                       type: .objcHeader),
                         output: .init(file: bridgingPrecompiledHeader,
                                       type: .pch))
    )
  }

  private mutating func addEmitModuleJob(addJob: (Job) -> Void) throws {
    if shouldCreateEmitModuleJob {
      addJob( try emitModuleJob() )
    }
  }

  private mutating func addJobsFeedingLinker(
    addJobBeforeCompiles: (Job) -> Void,
    addCompileJobGroup: (CompileJobGroup) -> Void,
    addJobAfterCompiles: (Job) -> Void
  ) throws -> [TypedVirtualPath] {

    var linkerInputs = [TypedVirtualPath]()
    func addLinkerInput(_ li: TypedVirtualPath) { linkerInputs.append(li) }

    var moduleInputs = [TypedVirtualPath]()
    let acceptBitcodeAsLinkerInput = lto == .llvmThin || lto == .llvmFull
    func addModuleInput(_ mi: TypedVirtualPath) { moduleInputs.append(mi) }
    var moduleInputsFromJobOutputs = [TypedVirtualPath]()
    func addModuleInputFromJobOutputs(_ mis: TypedVirtualPath) {
      moduleInputsFromJobOutputs.append(mis) }

    func addJobOutputs(_ jobOutputs: [TypedVirtualPath]) {
      for jobOutput in jobOutputs {
        switch jobOutput.type {
          case .object, .autolink:
            addLinkerInput(jobOutput)
          case .llvmBitcode where acceptBitcodeAsLinkerInput:
            addLinkerInput(jobOutput)
          case .swiftModule:
            addModuleInputFromJobOutputs(jobOutput)

          default:
            break
        }
      }
    }

    try addSingleCompileJobs(addJob: addJobBeforeCompiles,
                             addJobOutputs: addJobOutputs,
                             emitModuleTrace: loadedModuleTracePath != nil)

    try addJobsForPrimaryInputs(
      addCompileJobGroup: addCompileJobGroup,
      addModuleInput: addModuleInput,
      addLinkerInput: addLinkerInput,
      addJobOutputs: addJobOutputs)

    try addAutolinkExtractJob(linkerInputs: linkerInputs,
                              addLinkerInput: addLinkerInput,
                              addJob: addJobAfterCompiles)

    if let mergeJob = try mergeModuleJob(
        moduleInputs: moduleInputs,
        moduleInputsFromJobOutputs: moduleInputsFromJobOutputs) {
      addJobAfterCompiles(mergeJob)
      try addVerifyJobs(mergeJob: mergeJob, addJob: addJobAfterCompiles)
      try addWrapJobOrMergeOutputs(
        mergeJob: mergeJob,
        debugInfo: debugInfo,
        addJob: addJobAfterCompiles,
        addLinkerInput: addLinkerInput)
    }
    return linkerInputs
  }

  private mutating func addSingleCompileJobs(
    addJob: (Job) -> Void,
    addJobOutputs: ([TypedVirtualPath]) -> Void,
    emitModuleTrace: Bool
  ) throws {
    guard case .singleCompile = compilerMode
    else { return }

    if parsedOptions.hasArgument(.embedBitcode),
       inputFiles.allSatisfy({ $0.type.isPartOfSwiftCompilation }) {
      let compile = try compileJob(primaryInputs: [],
                                   outputType: .llvmBitcode,
                                   addJobOutputs: addJobOutputs,
                                   emitModuleTrace: emitModuleTrace)
      addJob(compile)
      let backendJobs = try compile.outputs.compactMap { output in
        output.type == .llvmBitcode
          ? try backendJob(input: output, addJobOutputs: addJobOutputs)
          : nil
      }
      backendJobs.forEach(addJob)
    } else {
      // We can skip the compile jobs if all we want is a module when it's
      // built separately.
      let compile = try compileJob(primaryInputs: [],
                                   outputType: compilerOutputType,
                                   addJobOutputs: addJobOutputs,
                                   emitModuleTrace: emitModuleTrace)
      addJob(compile)
    }
  }

  private mutating func addJobsForPrimaryInputs(
    addCompileJobGroup: (CompileJobGroup) -> Void,
    addModuleInput: (TypedVirtualPath) -> Void,
    addLinkerInput: (TypedVirtualPath) -> Void,
    addJobOutputs: ([TypedVirtualPath]) -> Void)
  throws {
    let loadedModuleTraceInputIndex = inputFiles.firstIndex(where: {
      $0.type.isPartOfSwiftCompilation && loadedModuleTracePath != nil
    })
    for (index, input) in inputFiles.enumerated() {
      // Only emit a loaded module trace from the first frontend job.
      try addJobForPrimaryInput(
        input: input,
        addCompileJobGroup: addCompileJobGroup,
        addModuleInput: addModuleInput,
        addLinkerInput: addLinkerInput,
        addJobOutputs: addJobOutputs,
        emitModuleTrace: index == loadedModuleTraceInputIndex)
    }
  }

  private mutating func addJobForPrimaryInput(
    input: TypedVirtualPath,
    addCompileJobGroup: (CompileJobGroup) -> Void,
    addModuleInput: (TypedVirtualPath) -> Void,
    addLinkerInput: (TypedVirtualPath) -> Void,
    addJobOutputs: ([TypedVirtualPath]) -> Void,
    emitModuleTrace: Bool
  ) throws
  {
    switch input.type {
    case .swift, .sil, .sib:
      // Generate a compile job for primary inputs here.
      guard compilerMode.usesPrimaryFileInputs else { break }

       assert(input.type.isPartOfSwiftCompilation)
      // We can skip the compile jobs if all we want is a module when it's
      // built separately.
      let canSkipIfOnlyModule = compilerOutputType == .swiftModule && shouldCreateEmitModuleJob
      try createAndAddCompileJobGroup(primaryInput: input,
                                      emitModuleTrace: emitModuleTrace,
                                      canSkipIfOnlyModule: canSkipIfOnlyModule,
                                      addCompileJobGroup: addCompileJobGroup,
                                      addJobOutputs: addJobOutputs)

    case .object, .autolink, .llvmBitcode:
      if linkerOutputType != nil {
        addLinkerInput(input)
      } else {
        diagnosticEngine.emit(.error_unexpected_input_file(input.file))
      }

    case .swiftModule:
      if moduleOutputInfo.output != nil && linkerOutputType == nil {
        // When generating a .swiftmodule as a top-level output (as opposed
        // to, for example, linking an image), treat .swiftmodule files as
        // inputs to a MergeModule action.
        addModuleInput(input)
      } else if linkerOutputType != nil {
        // Otherwise, if linking, pass .swiftmodule files as inputs to the
        // linker, so that their debug info is available.
        addLinkerInput(input)
      } else {
        diagnosticEngine.emit(.error_unexpected_input_file(input.file))
      }

    default:
      diagnosticEngine.emit(.error_unexpected_input_file(input.file))
    }
  }

  private mutating func createAndAddCompileJobGroup(
    primaryInput: TypedVirtualPath,
    emitModuleTrace: Bool,
    canSkipIfOnlyModule: Bool,
    addCompileJobGroup: (CompileJobGroup) -> Void,
    addJobOutputs: ([TypedVirtualPath]) -> Void
  )  throws {
    if parsedOptions.hasArgument(.embedBitcode),
       inputFiles.allSatisfy({ $0.type.isPartOfSwiftCompilation }) {
      let compile = try compileJob(primaryInputs: [primaryInput],
                                   outputType: .llvmBitcode,
                                   addJobOutputs: addJobOutputs,
                                   emitModuleTrace: emitModuleTrace)
      let backendJobs = try compile.outputs.compactMap { output in
        output.type == .llvmBitcode
          ? try backendJob(input: output, addJobOutputs: addJobOutputs)
          : nil
      }
      assert(backendJobs.count <= 1)
      addCompileJobGroup(CompileJobGroup(compileJob: compile, backendJob: backendJobs.first))
    } else if !canSkipIfOnlyModule {
      // We can skip the compile jobs if all we want is a module when it's
      // built separately.
      let compile = try compileJob(primaryInputs: [primaryInput],
                                   outputType: compilerOutputType,
                                   addJobOutputs: addJobOutputs,
                                   emitModuleTrace: emitModuleTrace)
      addCompileJobGroup(CompileJobGroup(compileJob: compile, backendJob: nil))
    }
  }

  /// Need a merge module job if there are module inputs
  private mutating func mergeModuleJob(
    moduleInputs: [TypedVirtualPath],
    moduleInputsFromJobOutputs: [TypedVirtualPath]
  ) throws -> Job? {
    guard moduleOutputInfo.output != nil,
          !(moduleInputs.isEmpty && moduleInputsFromJobOutputs.isEmpty),
          compilerMode.usesPrimaryFileInputs
    else { return nil }
    return try mergeModuleJob(inputs: moduleInputs, inputsFromOutputs: moduleInputsFromJobOutputs)
  }

  private mutating func addVerifyJobs(mergeJob: Job, addJob: (Job) -> Void )
  throws {
    guard
       parsedOptions.hasArgument(.enableLibraryEvolution),
       parsedOptions.hasFlag(positive: .verifyEmittedModuleInterface,
                             negative: .noVerifyEmittedModuleInterface,
                             default: false)
    else { return }

    func addVerifyJob(forPrivate: Bool) throws {
      let isNeeded =
        forPrivate
        ? parsedOptions.hasArgument(.emitPrivateModuleInterfacePath)
        : parsedOptions.hasArgument(.emitModuleInterface, .emitModuleInterfacePath)
      guard isNeeded else { return }

      let outputType: FileType =
        forPrivate ? .privateSwiftInterface : .swiftInterface
      let mergeInterfaceOutputs = mergeJob.outputs.filter { $0.type == outputType }
      assert(mergeInterfaceOutputs.count == 1,
             "Merge module job should only have one swiftinterface output")
      let job = try verifyModuleInterfaceJob(interfaceInput: mergeInterfaceOutputs[0])
      addJob(job)
    }
    try addVerifyJob(forPrivate: false)
    try addVerifyJob(forPrivate: true )
  }

  private mutating func addAutolinkExtractJob(
    linkerInputs: [TypedVirtualPath],
    addLinkerInput: (TypedVirtualPath) -> Void,
    addJob: (Job) -> Void)
  throws
  {
    let autolinkInputs = linkerInputs.filter { $0.type == .object }
    if let autolinkExtractJob = try autolinkExtractJob(inputs: autolinkInputs) {
      addJob(autolinkExtractJob)
      autolinkExtractJob.outputs.forEach(addLinkerInput)
    }
  }

  private mutating func addWrapJobOrMergeOutputs(mergeJob: Job,
                                                 debugInfo: DebugInfo,
                                                 addJob: (Job) -> Void,
                                                 addLinkerInput: (TypedVirtualPath) -> Void)
  throws {
    guard case .astTypes = debugInfo.level
    else { return }
    if targetTriple.objectFormat != .macho {
      // Module wrapping is required.
      let mergeModuleOutputs = mergeJob.outputs.filter { $0.type == .swiftModule }
      assert(mergeModuleOutputs.count == 1,
             "Merge module job should only have one swiftmodule output")
      let wrapJob = try moduleWrapJob(moduleInput: mergeModuleOutputs[0])
      addJob(wrapJob)
      wrapJob.outputs.forEach(addLinkerInput)
    } else {
      let mergeModuleOutputs = mergeJob.outputs.filter { $0.type == .swiftModule }
      assert(mergeModuleOutputs.count == 1,
             "Merge module job should only have one swiftmodule output")
      addLinkerInput(mergeModuleOutputs[0])
    }
  }

  private mutating func addLinkAndPostLinkJobs(
    linkerInputs: [TypedVirtualPath],
    debugInfo: DebugInfo,
    addJob: (Job) -> Void
  ) throws {
    guard linkerOutputType != nil && !linkerInputs.isEmpty
    else { return }

    let linkJ = try linkJob(inputs: linkerInputs)
    addJob(linkJ)
    guard targetTriple.isDarwin, debugInfo.level != nil
    else {return }

    let dsymJob = try generateDSYMJob(inputs: linkJ.outputs)
    addJob(dsymJob)
    if debugInfo.shouldVerify {
      addJob(try verifyDebugInfoJob(inputs: dsymJob.outputs))
    }
  }

  /// Prescan the source files to produce a module dependency graph and turn it into a set
  /// of jobs required to build all dependencies.
  /// Preprocess the graph by resolving placeholder dependencies, if any are present and
  /// by re-scanning all Clang modules against all possible targets they will be built against.
  public mutating func generateExplicitModuleDependenciesJobs() throws -> [Job] {
    // Run the dependency scanner and update the dependency oracle with the results
    let dependencyGraph = try gatherModuleDependencies()

    // Plan build jobs for all direct and transitive module dependencies of the current target
    explicitDependencyBuildPlanner =
      try ExplicitDependencyBuildPlanner(dependencyGraph: dependencyGraph,
                                         toolchain: toolchain,
                                         integratedDriver: integratedDriver)

    return try explicitDependencyBuildPlanner!.generateExplicitModuleDependenciesBuildJobs()
  }

  private mutating func gatherModuleDependencies()
  throws -> InterModuleDependencyGraph {
    var dependencyGraph = try performDependencyScan()

    if externalBuildArtifacts != nil {
      // Resolve placeholder dependencies in the dependency graph, if any.
      // TODO: Should be deprecated once switched over to libSwiftScan in the clients
      try dependencyGraph.resolvePlaceholderDependencies(for: externalBuildArtifacts!,
                                                         using: interModuleDependencyOracle)

      try dependencyGraph.resolveExternalDependencies(for: externalBuildArtifacts!)
    }

    // Re-scan Clang modules at all the targets they will be built against.
    try resolveVersionedClangDependencies(dependencyGraph: &dependencyGraph)

    // Set dependency modules' paths to be saved in the module cache.
    try updateDependencyModulesWithModuleCachePath(dependencyGraph: &dependencyGraph)

    // Update the dependency oracle, adding this new dependency graph to its store
    try interModuleDependencyOracle.mergeModules(from: dependencyGraph)

    return dependencyGraph
  }

  /// Update the given inter-module dependency graph to set module paths to be within the module cache,
  /// if one is present.
  private mutating func updateDependencyModulesWithModuleCachePath(dependencyGraph:
                                                                    inout InterModuleDependencyGraph)
  throws {
    let moduleCachePath = parsedOptions.getLastArgument(.moduleCachePath)?.asSingle
    if moduleCachePath != nil {
      for (moduleId, moduleInfo) in dependencyGraph.modules {
        // Output path on the main module is determined by the invocation arguments.
        guard moduleId.moduleName != dependencyGraph.mainModuleName else {
          continue
        }
        let modulePath = moduleInfo.modulePath
        // Only update paths on modules which do not already specify a path beyond their module name
        // and a file extension.
        if modulePath.path.description == moduleId.moduleName + ".swiftmodule" ||
            modulePath.path.description == moduleId.moduleName + ".pcm" {
          // Use VirtualPath to get the OS-specific path separators right.
          let modulePathInCache =
            try VirtualPath(path: moduleCachePath!)
              .appending(component: modulePath.path.description)
          dependencyGraph.modules[moduleId]!.modulePath =
            TextualVirtualPath(path: modulePathInCache)
        }
      }
    }
  }

}

/// MARK: Planning
extension Driver {
  /// Create a job if needed for simple requests that can be immediately
  /// forwarded to the frontend.
  public mutating func immediateForwardingJob() throws -> Job? {
    if parsedOptions.hasArgument(.printTargetInfo) {
      let sdkPath = try parsedOptions.getLastArgument(.sdk).map { try VirtualPath(path: $0.asSingle) }
      let resourceDirPath = try parsedOptions.getLastArgument(.resourceDir).map { try VirtualPath(path: $0.asSingle) }

      return try toolchain.printTargetInfoJob(target: targetTriple,
                                              targetVariant: targetVariantTriple,
                                              sdkPath: sdkPath,
                                              resourceDirPath: resourceDirPath,
                                              requiresInPlaceExecution: true,
                                              useStaticResourceDir: useStaticResourceDir,
                                              swiftCompilerPrefixArgs: swiftCompilerPrefixArgs)
    }

    if parsedOptions.hasArgument(.version) || parsedOptions.hasArgument(.version_) {
      return Job(
        moduleName: moduleOutputInfo.name,
        kind: .versionRequest,
        tool: .absolute(try toolchain.getToolPath(.swiftCompiler)),
        commandLine: [.flag("--version")],
        inputs: [],
        primaryInputs: [],
        outputs: [],
        requiresInPlaceExecution: true)
    }

    if parsedOptions.contains(.help) || parsedOptions.contains(.helpHidden) {
      var commandLine: [Job.ArgTemplate] = [.flag(driverKind.rawValue)]
      if parsedOptions.contains(.helpHidden) {
        commandLine.append(.flag("-show-hidden"))
      }
      return Job(
        moduleName: moduleOutputInfo.name,
        kind: .help,
        tool: .absolute(try toolchain.getToolPath(.swiftHelp)),
        commandLine: commandLine,
        inputs: [],
        primaryInputs: [],
        outputs: [],
        requiresInPlaceExecution: true)
    }

    return nil
  }

  /// Plan a build by producing a set of jobs to complete the build.
  /// Should be private, but compiler bug
  /*private*/ mutating func planPossiblyIncrementalBuild() throws
  -> ([Job], IncrementalCompilationState?) {

    if let job = try immediateForwardingJob() {
      return ([job], nil)
    }

    // The REPL doesn't require input files, but all other modes do.
    guard !inputFiles.isEmpty || compilerMode == .repl else {
      if parsedOptions.hasArgument(.v) {
        // `swiftc -v` is allowed and prints version information.
        return ([], nil)
      }
      throw Error.noInputFiles
    }

    // Plan the build.
    switch compilerMode {
    case .repl:
      if !inputFiles.isEmpty {
        throw PlanningError.replReceivedInput
      }
      return ([try replJob()], nil)

    case .immediate:
      var jobs: [Job] = []
      try addPrecompileModuleDependenciesJobs(addJob: { jobs.append($0) })
      jobs.append(try interpretJob(inputs: inputFiles))
      return (jobs, nil)

    case .standardCompile, .batchCompile, .singleCompile:
      return try planStandardCompile()

    case .compilePCM:
      if inputFiles.count != 1 {
        throw PlanningError.emitPCMWrongInputFiles
      }
      return ([try generatePCMJob(input: inputFiles.first!)], nil)
    }
  }
}

extension Diagnostic.Message {
  static func error_unexpected_input_file(_ file: VirtualPath) -> Diagnostic.Message {
    .error("unexpected input file: \(file.name)")
  }
}

// MARK: Batch mode
extension Driver {

  /// Given some jobs, merge the compile jobs into batched jobs, as appropriate
  /// While it may seem odd to create unbatched jobs, then later disect and rebatch them,
  /// there are reasons for doing it this way:
  /// 1. For incremental builds, the inputs compiled in the 2nd wave cannot be known in advance, and
  /// 2. The code that creates a compile job intermixes command line formation, output gathering, etc.
  ///   It does this for good reason: these things are connected by consistency requirments, and
  /// 3. The outputs of all compilations are needed, not just 1st wave ones, to feed as inputs to the link job.
  ///
  /// So, in order to avoid making jobs and rebatching, the code would have to just get outputs for each
  /// compilation. But `compileJob` intermixes the output computation with other stuff.
  mutating func formBatchedJobs(_ jobs: [Job], showJobLifecycle: Bool) throws -> [Job] {
    guard compilerMode.isBatchCompile else {
      // Don't even go through the logic so as to not print out confusing
      // "batched foobar" messages.
      return jobs
    }
    let noncompileJobs = jobs.filter {$0.kind != .compile}
    let compileJobs = jobs.filter {$0.kind == .compile}
    let inputsAndJobs = compileJobs.flatMap { job in
      job.primaryInputs.map {($0, job)}
    }
    let jobsByInput = Dictionary(uniqueKeysWithValues: inputsAndJobs)
    // Try to preserve input order for easier testing
    let inputsInOrder = inputFiles.filter {jobsByInput[$0] != nil}

    let partitions = batchPartitions(
      inputs: inputsInOrder,
      showJobLifecycle: showJobLifecycle)
    let outputType = parsedOptions.hasArgument(.embedBitcode)
      ? .llvmBitcode
      : compilerOutputType

    let inputsRequiringModuleTrace = Set(
      compileJobs.filter { $0.outputs.contains {$0.type == .moduleTrace} }
        .flatMap {$0.primaryInputs}
    )

    let batchedCompileJobs = try inputsInOrder.compactMap { anInput -> Job? in
      let idx = partitions.assignment[anInput]!
      let primaryInputs = partitions.partitions[idx]
      guard primaryInputs[0] == anInput
      else {
        // This input file isn't the first
        // file in the partition, skip it: it's been accounted for already.
        return nil
      }
      if showJobLifecycle {
        // Log life cycle for added batch job
        primaryInputs.forEach {
          diagnosticEngine
            .emit(
              .remark(
                "Adding {compile: \($0.file.basename)} to batch \(idx)"))
        }

        let constituents = primaryInputs.map {$0.file.basename}.joined(separator: ", ")
        diagnosticEngine
          .emit(
            .remark(
              "Forming batch job from \(primaryInputs.count) constituents: \(constituents)"))
      }
      let constituentsEmittedModuleTrace = !inputsRequiringModuleTrace.intersection(primaryInputs).isEmpty
      // no need to add job outputs again
      return try compileJob(primaryInputs: primaryInputs,
                            outputType: outputType,
                            addJobOutputs: {_ in },
                            emitModuleTrace: constituentsEmittedModuleTrace)
    }
    return batchedCompileJobs + noncompileJobs
  }

  /// Determine the number of partitions we'll use for batch mode.
  private func numberOfBatchPartitions(
    _ info: BatchModeInfo?,
    numInputFiles: Int
  ) -> Int {
    guard numInputFiles > 0 else {
      return 0
    }
    guard let info = info else {
      return 1 // not batch mode
    }

    // If the number of partitions was specified by the user, use it
    if let fixedCount = info.count {
      return fixedCount
    }

    // This is a long comment to justify a simple calculation.
    //
    // Because there is a secondary "outer" build system potentially also
    // scheduling multiple drivers in parallel on separate build targets
    // -- while we, the driver, schedule our own subprocesses -- we might
    // be creating up to $NCPU^2 worth of _memory pressure_.
    //
    // Oversubscribing CPU is typically no problem these days, but
    // oversubscribing memory can lead to paging, which on modern systems
    // is quite bad.
    //
    // In practice, $NCPU^2 processes doesn't _quite_ happen: as core
    // count rises, it usually exceeds the number of large targets
    // without any dependencies between them (which are the only thing we
    // have to worry about): you might have (say) 2 large independent
    // modules * 2 architectures, but that's only an $NTARGET value of 4,
    // which is much less than $NCPU if you're on a 24 or 36-way machine.
    //
    //  So the actual number of concurrent processes is:
    //
    //     NCONCUR := $NCPU * min($NCPU, $NTARGET)
    //
    // Empirically, a frontend uses about 512kb RAM per non-primary file
    // and about 10mb per primary. The number of non-primaries per
    // process is a constant in a given module, but the number of
    // primaries -- the "batch size" -- is inversely proportional to the
    // batch count (default: $NCPU). As a result, the memory pressure
    // we can expect is:
    //
    //  $NCONCUR * (($NONPRIMARYMEM * $NFILE) +
    //              ($PRIMARYMEM * ($NFILE/$NCPU)))
    //
    // If we tabulate this across some plausible values, we see
    // unfortunate memory-pressure results:
    //
    //                          $NFILE
    //                  +---------------------
    //  $NTARGET $NCPU  |  100    500    1000
    //  ----------------+---------------------
    //     2        2   |  2gb   11gb    22gb
    //     4        4   |  4gb   24gb    48gb
    //     4        8   |  5gb   28gb    56gb
    //     4       16   |  7gb   36gb    72gb
    //     4       36   | 11gb   56gb   112gb
    //
    // As it happens, the lower parts of the table are dominated by
    // number of processes rather than the files-per-batch (the batches
    // are already quite small due to the high core count) and the left
    // side of the table is dealing with modules too small to worry
    // about. But the middle and upper-right quadrant is problematic: 4
    // and 8 core machines do not typically have 24-48gb of RAM, it'd be
    // nice not to page on them when building a 4-target project with
    // 500-file modules.
    //
    // Turns we can do that if we just cap the batch size statically at,
    // say, 25 files per batch, we get a better formula:
    //
    //  $NCONCUR * (($NONPRIMARYMEM * $NFILE) +
    //              ($PRIMARYMEM * min(25, ($NFILE/$NCPU))))
    //
    //                          $NFILE
    //                  +---------------------
    //  $NTARGET $NCPU  |  100    500    1000
    //  ----------------+---------------------
    //     2        2   |  1gb    2gb     3gb
    //     4        4   |  4gb    8gb    12gb
    //     4        8   |  5gb   16gb    24gb
    //     4       16   |  7gb   32gb    48gb
    //     4       36   | 11gb   56gb   108gb
    //
    // This means that the "performance win" of batch mode diminishes
    // slightly: the batching factor in the equation drops from
    // ($NFILE/$NCPU) to min(25, $NFILE/$NCPU). In practice this seems to
    // not cost too much: the additional factor in number of subprocesses
    // run is the following:
    //
    //                          $NFILE
    //                  +---------------------
    //  $NTARGET $NCPU  |  100    500    1000
    //  ----------------+---------------------
    //     2        2   |  2x    10x      20x
    //     4        4   |   -     5x      10x
    //     4        8   |   -   2.5x       5x
    //     4       16   |   -  1.25x     2.5x
    //     4       36   |   -      -     1.1x
    //
    // Where - means "no difference" because the batches were already
    // smaller than 25.
    //
    // Even in the worst case here, the 1000-file module on 2-core
    // machine is being built with only 40 subprocesses, rather than the
    // pre-batch-mode 1000. I.e. it's still running 96% fewer
    // subprocesses than before. And significantly: it's doing so while
    // not exceeding the RAM of a typical 2-core laptop.

    // An explanation of why the partition calculation isn't integer
    // division. Using an example, a module of 26 files exceeds the
    // limit of 25 and must be compiled in 2 batches. Integer division
    // yields 26/25 = 1 batch, but a single batch of 26 exceeds the
    // limit. The calculation must round up, which can be calculated
    // using: `(x + y - 1) / y`
    let divideRoundingUp = { num, div in
        return (num + div - 1) / div
    }

    let defaultSizeLimit = 25
    let sizeLimit = info.sizeLimit ?? defaultSizeLimit

    let numTasks = numParallelJobs ?? 1
    return max(numTasks, divideRoundingUp(numInputFiles, sizeLimit))
  }

  /// Describes the partitions used when batching.
  private struct BatchPartitions {
    /// Assignment of each Swift input file to a particular partition.
    /// The values are indices into `partitions`.
    let assignment: [TypedVirtualPath : Int]

    /// The contents of each partition.
    let partitions: [[TypedVirtualPath]]
  }

  private func batchPartitions(
    inputs: [TypedVirtualPath],
    showJobLifecycle: Bool
  ) -> BatchPartitions {
    let numScheduledPartitions = numberOfBatchPartitions(
      compilerMode.batchModeInfo,
      numInputFiles: inputs.count)

    if showJobLifecycle && inputs.count > 0 {
      diagnosticEngine
        .emit(
          .remark(
            "Found \(inputs.count) batchable job\(inputs.count != 1 ? "s" : "")"
          ))
      diagnosticEngine
        .emit(
          .remark(
            "Forming into \(numScheduledPartitions) batch\(numScheduledPartitions != 1 ? "es" : "")"
          ))
    }

    // If there is at most one partition, fast path.
    if numScheduledPartitions <= 1 {
      var assignment = [TypedVirtualPath: Int]()
      for input in inputs {
        assignment[input] = 0
      }
      let partitions = inputs.isEmpty ? [] : [inputs]
      return BatchPartitions(assignment: assignment,
                             partitions: partitions)
    }

    // Map each input file to a partition index. Ensure that we evenly
    // distribute the remainder.
    let numScheduledInputFiles = inputs.count
    let remainder = numScheduledInputFiles % numScheduledPartitions
    let targetSize = numScheduledInputFiles / numScheduledPartitions
    var partitionIndices: [Int] = []
    for partitionIdx in 0..<numScheduledPartitions {
      let fillCount = targetSize + (partitionIdx < remainder ? 1 : 0)
      partitionIndices.append(contentsOf: Array(repeating: partitionIdx, count: fillCount))
    }
    assert(partitionIndices.count == numScheduledInputFiles)

    guard let info = compilerMode.batchModeInfo else {
      fatalError("should be at most 1 partition if not in batch mode")
    }

    if let seed = info.seed {
      var generator = PredictableRandomNumberGenerator(seed: UInt64(seed))
      partitionIndices.shuffle(using: &generator)
    }

    // Form the actual partitions.
    var assignment: [TypedVirtualPath : Int] = [:]
    var partitions = Array<[TypedVirtualPath]>(repeating: [], count: numScheduledPartitions)
    for (fileIndex, file) in inputs.enumerated() {
      let partitionIdx = partitionIndices[fileIndex]
      assignment[file] = partitionIdx
      partitions[partitionIdx].append(file)
    }

    return BatchPartitions(assignment: assignment,
                           partitions: partitions)
  }
}
