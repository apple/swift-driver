//===--------------- IncrementalCompilationStateComputer.swift - Incremental -----------===//
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
import Foundation

/// Builds the IncrementalCompilationState
/// Also bundles up an bunch of configuration info

extension IncrementalCompilationState {

  public struct InitialStateComputer {
    @_spi(Testing) public let jobsInPhases: JobsInPhases
    @_spi(Testing) public let outputFileMap: OutputFileMap
    @_spi(Testing) public let buildRecordInfo: BuildRecordInfo
    @_spi(Testing) public let maybeBuildRecord: BuildRecord?
    @_spi(Testing) public let reporter: IncrementalCompilationState.Reporter?
    @_spi(Testing) public let inputFiles: [TypedVirtualPath]
    @_spi(Testing) public let fileSystem: FileSystem
    @_spi(Testing) public let showJobLifecycle: Bool
    @_spi(Testing) public let sourceFiles: SourceFiles
    @_spi(Testing) public let diagnosticEngine: DiagnosticsEngine
    @_spi(Testing) public let readPriorsFromModuleDependencyGraph: Bool
    @_spi(Testing) public let alwaysRebuildDependents: Bool
    @_spi(Testing) public let isCrossModuleIncrementalBuildEnabled: Bool
    @_spi(Testing) public let verifyDependencyGraphAfterEveryImport: Bool
    @_spi(Testing) public let emitDependencyDotFileAfterEveryImport: Bool
    
    /// Options, someday
    @_spi(Testing) public let dependencyDotFilesIncludeExternals: Bool = true
    @_spi(Testing) public let dependencyDotFilesIncludeAPINotes: Bool = false

    @_spi(Testing) public let buildTime: Date

    @_spi(Testing) public init(
      _ options: IncrementalCompilationState.Options,
      _ jobsInPhases: JobsInPhases,
      _ outputFileMap: OutputFileMap,
      _ buildRecordInfo: BuildRecordInfo,
      _ buildRecord: BuildRecord?,
      _ reporter: IncrementalCompilationState.Reporter?,
      _ inputFiles: [TypedVirtualPath],
      _ fileSystem: FileSystem,
      showJobLifecycle: Bool,
      _ diagnosticEngine: DiagnosticsEngine
    ) {
      self.jobsInPhases = jobsInPhases
      self.outputFileMap = outputFileMap
      self.buildRecordInfo = buildRecordInfo
      self.maybeBuildRecord = buildRecord
      self.reporter = reporter
      self.inputFiles = inputFiles
      self.fileSystem = fileSystem
      self.showJobLifecycle = showJobLifecycle
      assert(outputFileMap.onlySourceFilesHaveSwiftDeps())
      self.sourceFiles = SourceFiles(inputFiles: inputFiles,
                                     buildRecord: buildRecord)
      self.diagnosticEngine = diagnosticEngine
      // Do not try to reuse a graph from a different compilation, so check
      // the build record.
      self.readPriorsFromModuleDependencyGraph = maybeBuildRecord != nil &&
        options.contains(.readPriorsFromModuleDependencyGraph)
      self.alwaysRebuildDependents = options.contains(.alwaysRebuildDependents)
      self.isCrossModuleIncrementalBuildEnabled = options.contains(.enableCrossModuleIncrementalBuild)
      self.verifyDependencyGraphAfterEveryImport = options.contains(.verifyDependencyGraphAfterEveryImport)
      self.emitDependencyDotFileAfterEveryImport = options.contains(.emitDependencyDotFileAfterEveryImport)
      self.buildTime = maybeBuildRecord?.buildTime ?? .distantPast
    }

    func compute(batchJobFormer: inout Driver)
    throws -> InitialState? {
      guard sourceFiles.disappeared.isEmpty else {
        // Would have to cleanse nodes of disappeared inputs from graph
        // and would have to schedule files dependening on defs from disappeared nodes
        if let reporter = reporter {
          reporter.report(
            "Incremental compilation has been disabled, " +
              " because  the following inputs were used in the previous compilation but not in this one: "
              + sourceFiles.disappeared.map {VirtualPath.lookup($0).basename} .joined(separator: ", "))
        }
        return nil
      }

      guard let (graph, inputsInvalidatedByExternals) =
              computeGraphAndInputsInvalidatedByExternals()
      else {
        return nil
      }
      let (skippedCompileGroups: skippedCompileGroups, mandatoryJobsInOrder) =
        try computeInputsAndGroups(
          graph,
          inputsInvalidatedByExternals,
          batchJobFormer: &batchJobFormer)

      return InitialState(graph: graph,
                          skippedCompileGroups: skippedCompileGroups,
                          mandatoryJobsInOrder: mandatoryJobsInOrder)
    }
  }
}

// MARK: - building/reading the ModuleDependencyGraph & scheduling externals for 1st wave
extension IncrementalCompilationState.InitialStateComputer {

  /// Builds or reads the graph
  /// Returns nil if some input (i.e. .swift file) has no corresponding swiftdeps file.
  /// Does not cope with disappeared inputs -- would be left in graph
  /// For inputs with swiftDeps in OFM, but no readable file, puts input in graph map, but no nodes in graph:
  ///   caller must ensure scheduling of those
  private func computeGraphAndInputsInvalidatedByExternals()
  -> (ModuleDependencyGraph, TransitivelyInvalidatedInputSet)? {
    precondition(sourceFiles.disappeared.isEmpty,
                 "Would have to remove nodes from the graph if reading prior")
    if readPriorsFromModuleDependencyGraph {
      return readPriorGraphAndCollectInputsInvalidatedByChangedOrAddedExternals()
    }
    // Every external is added, but don't want to compile an unchanged input that has an import
    // so just changed, not changedOrAdded
    return buildInitialGraphFromSwiftDepsAndCollectInputsInvalidatedByChangedExternals()
  }

  private func readPriorGraphAndCollectInputsInvalidatedByChangedOrAddedExternals(
  ) -> (ModuleDependencyGraph, TransitivelyInvalidatedInputSet)?
  {
    let dependencyGraphPath = buildRecordInfo.dependencyGraphPath
    let graphIfPresent: ModuleDependencyGraph?
    do {
      graphIfPresent = try ModuleDependencyGraph.read( from: dependencyGraphPath, info: self)
    }
    catch {
      diagnosticEngine.emit(
        warning: "Could not read \(dependencyGraphPath), will not do cross-module incremental builds")
      graphIfPresent = nil
    }
    guard let graph = graphIfPresent
    else {
      return buildInitialGraphFromSwiftDepsAndCollectInputsInvalidatedByChangedExternals()
    }
    guard graph.populateInputDependencySourceMap() else {
      return nil
    }
    graph.dotFileWriter?.write(graph)

    // Any externals not already in graph must be additions which should trigger
    // recompilation. Thus, `ChangedOrAdded`.
    let nodesDirectlyInvalidatedByExternals = graph.collectNodesInvalidatedByChangedOrAddedExternals()
    // Wait till the last minute to do the transitive closure as an optimization.
    let inputsInvalidatedByExternals = graph.collectInputsUsingInvalidated(
      nodes: nodesDirectlyInvalidatedByExternals)
    return (graph, inputsInvalidatedByExternals)
  }

  /// Builds a graph
  /// Returns nil if some input (i.e. .swift file) has no corresponding swiftdeps file.
  /// Does not cope with disappeared inputs
  /// For inputs with swiftDeps in OFM, but no readable file, puts input in graph map, but no nodes in graph:
  ///   caller must ensure scheduling of those
  /// For externalDependencies, puts then in graph.fingerprintedExternalDependencies, but otherwise
  /// does nothing special.
  private func buildInitialGraphFromSwiftDepsAndCollectInputsInvalidatedByChangedExternals(
  ) -> (ModuleDependencyGraph, TransitivelyInvalidatedInputSet)?
  {
    let graph = ModuleDependencyGraph(self, .buildingWithoutAPrior)
    assert(outputFileMap.onlySourceFilesHaveSwiftDeps())
    guard graph.populateInputDependencySourceMap() else {
      return nil
    }

    var inputsInvalidatedByChangedExternals = TransitivelyInvalidatedInputSet()
    for input in sourceFiles.currentInOrder {
       guard let invalidatedInputs = graph.collectInputsRequiringCompilationFromExternalsFoundByCompiling(input: input)
      else {
        return nil
      }
      inputsInvalidatedByChangedExternals.formUnion(invalidatedInputs)
    }
    reporter?.report("Created dependency graph from swiftdeps files")
    return (graph, inputsInvalidatedByChangedExternals)
  }
}

// MARK: - Preparing the first wave
extension IncrementalCompilationState.InitialStateComputer {

  /// At this stage the graph will have all external dependencies found in the swiftDeps or in the priors
  /// listed in fingerprintExternalDependencies.
  private func computeInputsAndGroups(
    _ moduleDependencyGraph: ModuleDependencyGraph,
    _ inputsInvalidatedByExternals: TransitivelyInvalidatedInputSet,
    batchJobFormer: inout Driver
  ) throws -> (skippedCompileGroups: [TypedVirtualPath: CompileJobGroup],
               mandatoryJobsInOrder: [Job])
  {
    precondition(sourceFiles.disappeared.isEmpty, "unimplemented")
    let compileGroups =
      Dictionary(uniqueKeysWithValues:
                  jobsInPhases.compileGroups.map { ($0.primaryInput, $0) })
    guard let buildRecord = maybeBuildRecord else {
      let mandatoryCompileGroupsInOrder = sourceFiles.currentInOrder.compactMap {
        input -> CompileJobGroup? in
        compileGroups[input]
      }

      let mandatoryJobsInOrder = try
        jobsInPhases.beforeCompiles +
        batchJobFormer.formBatchedJobs(
          mandatoryCompileGroupsInOrder.flatMap {$0.allJobs()},
          showJobLifecycle: showJobLifecycle)

      moduleDependencyGraph.phase = .buildingAfterEachCompilation
      return (skippedCompileGroups: [:],
              mandatoryJobsInOrder: mandatoryJobsInOrder)
    }
    moduleDependencyGraph.phase = .updatingAfterCompilation


    let skippedInputs = computeSkippedCompilationInputs(
      inputsInvalidatedByExternals: inputsInvalidatedByExternals,
      moduleDependencyGraph,
      buildRecord)

    let skippedCompileGroups = compileGroups.filter {skippedInputs.contains($0.key)}

    let mandatoryCompileGroupsInOrder = inputFiles.compactMap {
      input -> CompileJobGroup? in
      skippedInputs.contains(input)
        ? nil
        : compileGroups[input]
    }

    let mandatoryJobsInOrder = try
      jobsInPhases.beforeCompiles +
      batchJobFormer.formBatchedJobs(
        mandatoryCompileGroupsInOrder.flatMap {$0.allJobs()},
        showJobLifecycle: showJobLifecycle)

    return (skippedCompileGroups: skippedCompileGroups,
            mandatoryJobsInOrder: mandatoryJobsInOrder)
  }

  /// Figure out which compilation inputs are *not* mandatory
  private func computeSkippedCompilationInputs(
    inputsInvalidatedByExternals: TransitivelyInvalidatedInputSet,
    _ moduleDependencyGraph: ModuleDependencyGraph,
    _ buildRecord: BuildRecord
  ) -> Set<TypedVirtualPath> {
    let allGroups = jobsInPhases.compileGroups
    // Input == source file
    let changedInputs = computeChangedInputs( moduleDependencyGraph, buildRecord)

    if let reporter = reporter {
      for input in inputsInvalidatedByExternals {
        reporter.report("Invalidated externally; will queue", input)
      }
    }

    let inputsHavingMalformedDependencySources =
      sourceFiles.currentInOrder.filter { sourceFile in
        !moduleDependencyGraph.containsNodes(forSourceFile: sourceFile)}

    if let reporter = reporter {
      for input in inputsHavingMalformedDependencySources {
        reporter.report("Has malformed dependency source; will queue", input)
      }
    }
    let inputsMissingOutputs = allGroups.compactMap {
      $0.outputs.contains {(try? !fileSystem.exists($0.file)) ?? true}
        ? $0.primaryInput
        : nil
    }
    if let reporter = reporter {
      for input in inputsMissingOutputs {
        reporter.report("Missing an output; will queue", input)
      }
    }

    // Combine to obtain the inputs that definitely must be recompiled.
    let definitelyRequiredInputs =
      Set(changedInputs.map({ $0.filePath }) +
            inputsInvalidatedByExternals +
            inputsHavingMalformedDependencySources +
            inputsMissingOutputs)
    if let reporter = reporter {
      for scheduledInput in sortByCommandLineOrder(definitelyRequiredInputs) {
        reporter.report("Queuing (initial):", scheduledInput)
      }
    }

    // Sometimes, inputs run in the first wave that depend on the changed inputs for the
    // first wave, even though they may not require compilation.
    // Any such inputs missed, will be found by the rereading of swiftDeps
    // as each first wave job finished.
    let speculativeInputs = collectInputsToBeSpeculativelyRecompiled(
      changedInputs: changedInputs,
      externalDependents: inputsInvalidatedByExternals,
      inputsMissingOutputs: Set(inputsMissingOutputs),
      moduleDependencyGraph)
      .subtracting(definitelyRequiredInputs)

    if let reporter = reporter {
      for dependent in sortByCommandLineOrder(speculativeInputs) {
        reporter.report("Queuing because of the initial set:", dependent)
      }
    }
    let immediatelyCompiledInputs = definitelyRequiredInputs.union(speculativeInputs)

    let skippedInputs = Set(buildRecordInfo.compilationInputModificationDates.keys)
      .subtracting(immediatelyCompiledInputs)
    if let reporter = reporter {
      for skippedInput in sortByCommandLineOrder(skippedInputs)  {
        reporter.report("Skipping input:", skippedInput)
      }
    }
    return skippedInputs
  }

  private func sortByCommandLineOrder(_ inputs: Set<TypedVirtualPath>) -> [TypedVirtualPath] {
    let indices = Dictionary(uniqueKeysWithValues: inputs.enumerated()
                              .map {offset, element in (element, offset)})
    return inputs.sorted {indices[$0]! < indices[$1]!}
  }

  /// Encapsulates information about an input the driver has determined has
  /// changed in a way that requires an incremental rebuild.
  struct ChangedInput {
    /// The path to the input file.
    let filePath: TypedVirtualPath
    /// The status of the input file.
    let status: InputInfo.Status
    /// If `true`, the modification time of this input matches the modification
    /// time recorded from the prior build in the build record.
    let datesMatch: Bool
  }

  /// Find the inputs that have changed since last compilation, or were marked as needed a build
  private func computeChangedInputs(
    _ moduleDependencyGraph: ModuleDependencyGraph,
    _ outOfDateBuildRecord: BuildRecord
  ) -> [ChangedInput] {
    jobsInPhases.compileGroups.compactMap { group in
      let input = group.primaryInput
      let modDate = buildRecordInfo.compilationInputModificationDates[input]
        ?? Date.distantFuture
      let inputInfo = outOfDateBuildRecord.inputInfos[input.fileHandle]
      let previousCompilationStatus = inputInfo?.status ?? .newlyAdded
      let previousModTime = inputInfo?.previousModTime

      // Because legacy driver reads/writes dates wrt 1970,
      // and because converting time intervals to/from Dates from 1970
      // exceeds Double precision, must not compare dates directly
      var datesMatch: Bool {
        modDate.timeIntervalSince1970 == previousModTime?.timeIntervalSince1970
      }

      switch previousCompilationStatus {
      case .upToDate where datesMatch:
        reporter?.report("May skip current input:", input)
        return nil

      case .upToDate:
        reporter?.report("Scheduing changed input", input)
      case .newlyAdded:
        reporter?.report("Scheduling new", input)
      case .needsCascadingBuild:
        reporter?.report("Scheduling cascading build", input)
      case .needsNonCascadingBuild:
        reporter?.report("Scheduling noncascading build", input)
      }
      return ChangedInput(filePath: input,
                          status: previousCompilationStatus,
                          datesMatch: datesMatch)
    }
  }

  /// Returns the cascaded files to compile in the first wave, even though it may not be need.
  /// The needs[Non}CascadingBuild stuff was cargo-culted from the legacy driver.
  /// TODO: something better, e.g. return nothing here, but process changed dependencySource
  /// before the whole frontend job finished.
  private func collectInputsToBeSpeculativelyRecompiled(
    changedInputs: [ChangedInput],
    externalDependents: TransitivelyInvalidatedInputSet,
    inputsMissingOutputs: Set<TypedVirtualPath>,
    _ moduleDependencyGraph: ModuleDependencyGraph
  ) -> Set<TypedVirtualPath> {
    let cascadingChangedInputs = computeCascadingChangedInputs(
      from: changedInputs,
      inputsMissingOutputs: inputsMissingOutputs)

    var inputsToBeCertainlyRecompiled = alwaysRebuildDependents ? externalDependents : TransitivelyInvalidatedInputSet()
    inputsToBeCertainlyRecompiled.formUnion(cascadingChangedInputs)

    return inputsToBeCertainlyRecompiled.reduce(into: Set()) {
      speculativelyRecompiledInputs, certainlyRecompiledInput in
      let speculativeDependents = moduleDependencyGraph.collectInputsInvalidatedBy(input: certainlyRecompiledInput)
      for speculativeDependent in speculativeDependents
      where !inputsToBeCertainlyRecompiled.contains(speculativeDependent) {
        if speculativelyRecompiledInputs.insert(speculativeDependent).inserted {
          reporter?.report(
            "Immediately scheduling dependent on \(certainlyRecompiledInput.file.basename)", speculativeDependent)
        }
      }
    }
  }

  // Collect the files that will be compiled whose dependents should be schedule
  private func computeCascadingChangedInputs(
    from changedInputs: [ChangedInput],
    inputsMissingOutputs: Set<TypedVirtualPath>
  ) -> [TypedVirtualPath] {
    changedInputs.compactMap { changedInput in
      let inputIsUpToDate =
        changedInput.datesMatch && !inputsMissingOutputs.contains(changedInput.filePath)
      let basename = changedInput.filePath.file.basename

      // If we're asked to always rebuild dependents, all we need to do is
      // return inputs whose modification times have changed.
      guard !alwaysRebuildDependents else {
        if inputIsUpToDate {
          reporter?.report(
            "not scheduling dependents of \(basename) despite -driver-always-rebuild-dependents because is up to date")
          return nil
        } else {
          reporter?.report(
            "scheduling dependents of \(basename); -driver-always-rebuild-dependents")
          return changedInput.filePath
        }
      }

      switch changedInput.status {
      case .needsCascadingBuild:
        reporter?.report(
          "scheduling dependents of \(basename); needed cascading build")
        return changedInput.filePath
      case .upToDate:
        reporter?.report(
          "not scheduling dependents of \(basename); unknown changes")
        return nil
      case .newlyAdded:
        reporter?.report(
          "not scheduling dependents of \(basename): no entry in build record or dependency graph")
        return nil
      case .needsNonCascadingBuild:
        reporter?.report(
          "not scheduling dependents of \(basename): does not need cascading build")
        return nil
      }
    }
  }
}
