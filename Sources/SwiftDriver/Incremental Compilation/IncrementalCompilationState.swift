//===--------------- IncrementalCompilation.swift - Incremental -----------===//
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
import SwiftOptions
@_spi(Testing) public class IncrementalCompilationState {
  public let buildRecordInfo: BuildRecordInfo
  public let diagnosticEngine: DiagnosticsEngine
  public let moduleDependencyGraph: ModuleDependencyGraph
  public let outOfDateBuildRecord: BuildRecord
  public let reportIncrementalDecision: (String) -> Void
  public let reportIncrementalQueuing: (String, VirtualPath) -> Void

  /// The primary input files that are part of the first wave
  let firstWaveInputs: [TypedVirtualPath]

  /// First wave inputs that must be completed before second wave can start.
  /// Diminishes as build proceeds.
  var incompleteFirstWaveInputs: Set<TypedVirtualPath>

  /// Input files that were skipped.
  /// May shrink from first wave to second.
  var skippedCompilationInputs: Set<TypedVirtualPath>

  /// Jobs that were skipped.
  /// Redundant with `skippedCompilationInputs`
  /// TODO: Incremental. clean up someday
  var skippedCompileJobs = [TypedVirtualPath: Job]()

  /// Accumulates jobs to be run in 2nd wave
  public private(set) var jobsToBeRunInSecondWave = [Job]()

  /// Alerts driver when it can schedule the second wave
  public let secondWaveIsReady = DispatchSemaphore(value: 0)

  private var amHandlingJobCompletion = false

  /// Return nil if not compiling incrementally
  public init?(
    buildRecordInfo: BuildRecordInfo?,
    compilerMode: CompilerMode,
    diagnosticEngine: DiagnosticsEngine,
    fileSystem: FileSystem,
    inputFiles: [TypedVirtualPath],
    outputFileMap: OutputFileMap?,
    parsedOptions: inout ParsedOptions,
    showJobLifecycle: Bool
  ) {
    guard Self.shouldAttemptIncrementalCompilation(
            parsedOptions: &parsedOptions,
            compilerMode: compilerMode,
            diagnosticEngine: diagnosticEngine)
    else {
      return nil
    }


    let showIncrementalDecisions = parsedOptions.hasArgument(.driverShowIncremental) ||
      showJobLifecycle

    let reportIncrementalDecision =
         showIncrementalDecisions
         ? {diagnosticEngine.emit(.remark_incremental_decision(because: $0))}
         : {_ in }

    func reportIncrementalQueuingFn(_ s: String, _ p: VirtualPath) {
      let input = p.basenameWithoutExt + ".swift"
      let output = p.basenameWithoutExt + ".o"
      let message = "\(s) {compile: \(output) <= \(input)}"
      print(message)
      diagnosticEngine.emit(.remark_incremental_decision(because: message))
    }
    let reportIncrementalQueuing = showIncrementalDecisions
      ? reportIncrementalQueuingFn
      : {_, _ in}

    guard let outputFileMap = outputFileMap,
          let buildRecordInfo = buildRecordInfo
    else {
      diagnosticEngine.emit(.warning_incremental_requires_output_file_map)
      return nil
    }
    // FIXME: This should work without an output file map. We should have
    // another way to specify a build record and where to put intermediates.
    guard let outOfDateBuildRecord = buildRecordInfo.populateOutOfDateBuildRecord()
    else {
      return nil
    }
    if let mismatchReason = outOfDateBuildRecord.mismatchReason(
      buildRecordInfo: buildRecordInfo,
      inputFiles: inputFiles
    ) {
      diagnosticEngine.emit(.remark_incremental_compilation_disabled(because: mismatchReason))
      return nil
    }


    guard let moduleDependencyGraph =
            ModuleDependencyGraph.buildInitialGraph(
              diagnosticEngine: diagnosticEngine,
              inputs: buildRecordInfo.compilationInputModificationDates.keys,
              outputFileMap: outputFileMap,
              parsedOptions: &parsedOptions,
              remarkDisabled: Diagnostic.Message.remark_incremental_compilation_disabled,
              traceDependencies: showIncrementalDecisions)
    else {
      return nil
    }

    (firstWave: self.firstWaveInputs, skipped: self.skippedCompilationInputs)
      = Self.calculateScheduledAndSkippedCompilationInputs(
        buildRecordInfo: buildRecordInfo,
        moduleDependencyGraph: moduleDependencyGraph,
        outOfDateBuildRecord: outOfDateBuildRecord,
        reportIncrementalDecision: reportIncrementalDecision,
        reportIncrementalQueuing: reportIncrementalQueuing)

    self.incompleteFirstWaveInputs = Set(firstWaveInputs)
    self.moduleDependencyGraph = moduleDependencyGraph
    self.outOfDateBuildRecord = outOfDateBuildRecord
    self.reportIncrementalDecision = reportIncrementalDecision
    self.reportIncrementalQueuing = reportIncrementalQueuing
    self.diagnosticEngine = diagnosticEngine
    self.buildRecordInfo = buildRecordInfo

    signalSecondWaveReadinessWhenReady()
  }


  private static func shouldAttemptIncrementalCompilation(
    parsedOptions: inout ParsedOptions,
    compilerMode: CompilerMode,
    diagnosticEngine: DiagnosticsEngine
  ) -> Bool {
    guard parsedOptions.hasArgument(.incremental) else {
      return false
    }
    guard compilerMode.supportsIncrementalCompilation else {
      diagnosticEngine.emit(
        .remark_incremental_compilation_disabled(
          because: "it is not compatible with \(compilerMode)"))
      return false
    }
    guard !parsedOptions.hasArgument(.embedBitcode) else {
      diagnosticEngine.emit(
        .remark_incremental_compilation_disabled(
          because: "is not currently compatible with embedding LLVM IR bitcode"))
      return false
    }
    return true
  }
}

fileprivate extension CompilerMode {
  var supportsIncrementalCompilation: Bool {
    switch self {
    case .standardCompile, .immediate, .repl, .batchCompile: return true
    case .singleCompile, .compilePCM: return false
    }
  }
}

extension Diagnostic.Message {
  static var warning_incremental_requires_output_file_map: Diagnostic.Message {
    .warning("ignoring -incremental (currently requires an output file map)")
  }
  static var warning_incremental_requires_build_record_entry: Diagnostic.Message {
    .warning(
      "ignoring -incremental; " +
        "output file map has no master dependencies entry under \(FileType.swiftDeps)"
    )
  }
  static func remark_incremental_compilation_disabled(because why: String) -> Diagnostic.Message {
    .remark("Incremental compilation has been disabled, because \(why)")
  }
  static func remark_incremental_decision(because why: String) -> Diagnostic.Message {
    .remark("Incremental compilation decision: \(why)")
  }
}


// MARK: - Scheduling the first wave

/// It is convenient to record the inputs to be compiled immediately by returning the inputs to be skipped until
/// further notice.
extension IncrementalCompilationState {
  private static func calculateScheduledAndSkippedCompilationInputs(
    buildRecordInfo: BuildRecordInfo,
    moduleDependencyGraph: ModuleDependencyGraph,
    outOfDateBuildRecord: BuildRecord,
    reportIncrementalDecision: (String) -> Void,
    reportIncrementalQueuing: (String, VirtualPath) -> Void
  ) -> (firstWave: [TypedVirtualPath], skipped: Set<TypedVirtualPath>) {

    let changedInputs: [(TypedVirtualPath, InputInfo.Status)] = computeChangedInputs(
      buildRecordInfo: buildRecordInfo,
      moduleDependencyGraph: moduleDependencyGraph,
      outOfDateBuildRecord: outOfDateBuildRecord,
      reportIncrementalDecision: reportIncrementalDecision
    )
    let externalDependents = computeExternallyDependentInputs(
      buildTime: outOfDateBuildRecord.buildTime,
      fileSystem: buildRecordInfo.fileSystem,
      moduleDependencyGraph: moduleDependencyGraph,
      reportIncrementalDecision: reportIncrementalDecision)
    // Combine the first to obtain the inputs that definitely must be recompiled.
    let inputsRequiringCompilation = Set(changedInputs.map {$0.0} + externalDependents)
    for scheduledInput in inputsRequiringCompilation.sorted(by: {$0.file.name < $1.file.name}) {
      reportIncrementalQueuing("Queuing (initial):", scheduledInput.file)
    }

    // Sometimes, schedule inputs that depend on the changed inputs for the
    // first wave, even though they may not require compilation.
    // Any such inputs missed, will be found by the rereading of swiftDeps
    // as each first wave job finished.
    let speculativelyScheduledInputs = computeDependentsToSpeculativelySchedule(
      changedInputs: changedInputs,
      moduleDependencyGraph: moduleDependencyGraph,
      reportIncrementalDecision: reportIncrementalDecision)
    let additions = speculativelyScheduledInputs.subtracting(inputsRequiringCompilation)
    for addition in additions.sorted(by: {$0.file.name < $1.file.name}) {
      reportIncrementalQueuing("Queuing (dependent):", addition.file)
    }
    let scheduledInputs = Array(inputsRequiringCompilation.union(additions))
      .sorted {$0.file.name < $1.file.name}

    let skippedCompilationInputs = Set(buildRecordInfo.compilationInputModificationDates.keys)
      .subtracting(scheduledInputs)
    for skippedInput in skippedCompilationInputs.sorted(by: {$0.file.name < $1.file.name})  {
      reportIncrementalQueuing("Skipping:", skippedInput.file)
    }
    return (firstWave: scheduledInputs, skipped: skippedCompilationInputs)
  }

  /// Find the inputs that have changed since last compilation, or were marked as needed a build
  private static func computeChangedInputs(
    buildRecordInfo: BuildRecordInfo,
    moduleDependencyGraph: ModuleDependencyGraph,
    outOfDateBuildRecord: BuildRecord,
    reportIncrementalDecision: (String) -> Void
   ) -> [(TypedVirtualPath, InputInfo.Status)] {
    buildRecordInfo.compilationInputModificationDates.filter { input, _ in
      input.type.isPartOfSwiftCompilation
    }
    .sorted {$0.key.file.name < $1.key.file.name}
    .compactMap { input, modDate in
      let previousCompilationStatus = outOfDateBuildRecord
        .inputInfos[input.file]?.status ?? .newlyAdded

      let basename = input.file.basename

      switch previousCompilationStatus {
      // Using outOfDateBuildRecord.inputInfos[input.file]?.previousModTime
      // has some inaccuracy.
      // Use outOfDateBuildRecord.buildTime instead
      case .upToDate where modDate < outOfDateBuildRecord.buildTime:
        reportIncrementalDecision("\(basename) is current; skipping")
        return nil
      case .upToDate:
        reportIncrementalDecision("\(basename) has changed; scheduling")
      case .newlyAdded:
        reportIncrementalDecision(
          "\(basename) was not compiled before; scheduling")
      case .needsCascadingBuild:
        reportIncrementalDecision(
          "\(basename) needs a cascading build; scheduling")
      case .needsNonCascadingBuild:
        reportIncrementalDecision(
          "\(basename) needs a non-cascading build; scheduling")
      }
      return (input, previousCompilationStatus)
    }
  }

  /// Any files dependent on modified files from other modules must be compiled, too.
  private static func computeExternallyDependentInputs(
    buildTime: Date,
    fileSystem: FileSystem,
    moduleDependencyGraph: ModuleDependencyGraph,
    reportIncrementalDecision: (String) -> Void
 ) -> [TypedVirtualPath] {
    var externallyDependentSwiftDeps = Set<ModuleDependencyGraph.SwiftDeps>()
    for extDep in moduleDependencyGraph.externalDependencies {
      let extModTime = extDep.file.flatMap {
        try? fileSystem.getFileInfo($0).modTime}
        ?? Date.distantFuture
      if extModTime >= buildTime {
        moduleDependencyGraph.forEachUntracedSwiftDepsDirectlyDependent(on: extDep) {
          reportIncrementalDecision(
            "scheduling \($0.file.basename), depends on newer \(extDep.file?.basename ?? "extDep?")")
          externallyDependentSwiftDeps.insert($0)
        }
      }
    }
    return externallyDependentSwiftDeps.compactMap {
      moduleDependencyGraph.sourceSwiftDepsMap[$0]
    }
  }

  /// Returns the cascaded files to compile in the first wave, even though it may not be need.
  /// The needs[Non}CascadingBuild stuff was cargo-culted from the legacy driver.
  /// TODO: something better, e.g. return nothing here, but process changes swiftDeps from 1st wave
  /// before the whole frontend job finished.
  private static func computeDependentsToSpeculativelySchedule(
    changedInputs: [(TypedVirtualPath, InputInfo.Status)],
    moduleDependencyGraph: ModuleDependencyGraph,
    reportIncrementalDecision: (String) -> Void
    ) -> Set<TypedVirtualPath> {
    // Collect the files that will be compiled whose dependents should be schedule
    let cascadingFiles: [TypedVirtualPath] = changedInputs.compactMap { input, status in
      let basename = input.file.basename
      switch status {
      case .needsCascadingBuild:
        reportIncrementalDecision(
          "scheduling dependents of \(basename); needed cascading build")
        return input
      case .upToDate: // Must be building because it changed
        reportIncrementalDecision(
          "not scheduling dependents of \(basename); unknown changes")
        return nil
       case .newlyAdded:
        reportIncrementalDecision(
          "not scheduling dependents of \(basename): no entry in build record or dependency graph")
        return nil
      case .needsNonCascadingBuild:
        reportIncrementalDecision(
          "not scheduling dependents of \(basename): does not need cascading build")
        return nil
      }
    }
    // Collect the dependent files to speculatively schedule
    var dependentFiles = Set<TypedVirtualPath>()
    let cascadingFileSet = Set(cascadingFiles)
    for cascadingFile in cascadingFiles {
       let dependentsOfOneFile = moduleDependencyGraph
        .findDependentSourceFiles(of: cascadingFile, reportIncrementalDecision)
      for dep in dependentsOfOneFile where !cascadingFileSet.contains(dep) {
        if dependentFiles.insert(dep).0 {
          reportIncrementalDecision(
            "immediately scheduling \(dep.file.basename) which depends on \(cascadingFile.file.basename)")
        }
      }
    }
    return dependentFiles
  }
}

// MARK: - Scheduling 2nd wave
extension IncrementalCompilationState {
  func addSkippedCompileJobs(_ jobs: [Job]) {
    for job in jobs {
      reportIncrementalDecision("Skipping \(job.descriptionForLifecycle)")
      for input in job.primaryInputs {
        if let _ = skippedCompileJobs.updateValue(job, forKey: input) {
          fatalError("should not have two skipped jobs for same skipped input")
        }
      }
    }
  }

  func addPostCompileJobs(_ jobs: [Job]) {
    for job in jobs {
      reportIncrementalDecision("Delaying \(job.descriptionForLifecycle) pending discovering delayed dependencies")
      willRunInSecondWave(job)
    }
  }

  func jobFinished(job: Job, result: ProcessResult) {
    defer {
      amHandlingJobCompletion = false
    }
    assert(!amHandlingJobCompletion, "was reentered, need to synchronize")
    amHandlingJobCompletion = true

    job.primaryInputs.forEach {incompleteFirstWaveInputs.remove($0)}

    let sourcesToSchedule = collectSourcesToScheduleAfterCompiling(job)
    for sourcesToSchedule in sourcesToSchedule {
      reportIncrementalQueuing(
        "Queuing because of dependencies discovered later:", sourcesToSchedule.file)
    }
    scheduleSecondWave(sourcesToSchedule)
    signalSecondWaveReadinessWhenReady()
 }

  private func collectSourcesToScheduleAfterCompiling(
    _ job: Job
  ) -> [TypedVirtualPath] {
    Array(
      Set(
        job.primaryInputs.flatMap {
          moduleDependencyGraph.findSourcesToCompileAfterCompiling($0)
            ?? Array(skippedCompilationInputs)
        }
      )
    )
    .sorted {$0.file.name < $1.file.name}
  }

  private func scheduleSecondWave(_ sources: [TypedVirtualPath]) {
    for input in sources {
      if let job = skippedCompileJobs.removeValue(forKey: input) {
        skippedCompilationInputs.subtract(job.primaryInputs)
        willRunInSecondWave(job)
      }
      else {
        reportIncrementalDecision("Tried to schedule 2nd wave input \(input.file.basename) again")
      }
    }
  }

  private func willRunInSecondWave(_ j: Job) {
    reportIncrementalDecision("Scheduling for 2nd wave \(j.descriptionForLifecycle)")
    jobsToBeRunInSecondWave.append(j)
  }

  private func signalSecondWaveReadinessWhenReady() {
    if incompleteFirstWaveInputs.isEmpty {
      // may get signalled > once, but doesn't matter
      secondWaveIsReady.signal()
    }
  }
}
