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

/// An instance of `IncrementalCompilationState` encapsulates the data necessary
/// to make incremental build scheduling decisions.
///
/// The primary form of interaction with the incremental compilation state is
/// using it as an oracle to discover the jobs to execute as the incremental
/// build progresses. After a job completes, call
/// `IncrementalCompilationState.collectJobsDiscoveredToBeNeededAfterFinishing(job:)`
/// to both update the incremental state and recieve an array of jobs that
/// need to be executed in response.
///
/// Jobs become "unstuck" as their inputs become available, or may be discovered
/// by this class as fresh dependency information is integrated.
///
/// Threading Considerations
/// ========================
///
/// The public API surface of this class is thread safe, but not re-entrant.
/// FIXME: This should be an actor.
public final class IncrementalCompilationState {

  /// The oracle for deciding what depends on what. Applies to this whole module.
  @_spi(Testing) public let moduleDependencyGraph: ModuleDependencyGraph

  /// If non-null outputs information for `-driver-show-incremental` for input path
  private let reporter: Reporter?

  /// All of the pre-compile or compilation job (groups) known to be required (i.e. in 1st wave).
  /// Already batched, and in order of input files.
  public let mandatoryJobsInOrder: [Job]

  /// Jobs to run *after* the last compile, for instance, link-editing.
  public let jobsAfterCompiles: [Job]

  /// A  high-priority confinement queue that must be used to protect the incremental compilation state.
  private let confinementQueue: DispatchQueue = DispatchQueue(label: "com.apple.swift-driver.incremental-compilation-state", qos: .userInteractive)

  /// Sadly, has to be `var` for formBatchedJobs
  ///
  /// After initialization, mutating accesses to the driver must be protected by
  /// the confinement queue.
  private var driver: Driver

  /// Keyed by primary input. As required compilations are discovered after the first wave, these shrink.
  ///
  /// This state is modified during the incremental build. All accesses must
  /// be protected by the confinement queue.
  private var skippedCompileGroups = [TypedVirtualPath: CompileJobGroup]()

// MARK: - Creating IncrementalCompilationState if possible
  /// Return nil if not compiling incrementally
  init?(
    driver: inout Driver,
    options: Options,
    jobsInPhases: JobsInPhases
  ) throws {
    guard driver.shouldAttemptIncrementalCompilation else { return nil }

    if options.contains(.showIncremental) {
      self.reporter = Reporter(diagnosticEngine: driver.diagnosticEngine,
                               outputFileMap: driver.outputFileMap)
    } else {
      self.reporter = nil
    }

    let enablingOrDisabling = options.contains(.enableCrossModuleIncrementalBuild)
      ? "Enabling"
      : "Disabling"
    reporter?.report(
      "\(enablingOrDisabling) incremental cross-module building")


    guard let outputFileMap = driver.outputFileMap else {
      driver.diagnosticEngine.emit(.warning_incremental_requires_output_file_map)
      return nil
    }

    guard let buildRecordInfo = driver.buildRecordInfo else {
      reporter?.reportDisablingIncrementalBuild("no build record path")
      return nil
    }

    // FIXME: This should work without an output file map. We should have
    // another way to specify a build record and where to put intermediates.
    let maybeBuildRecord = buildRecordInfo.populateOutOfDateBuildRecord(
            inputFiles: driver.inputFiles, reporter: reporter)

    // Forming batch jobs requires passing in the driver "inout". But that's the
    // only "inout" use needed, among many other values needed from the driver.
    // So, pass the other values individually, and pass the driver "inout" as
    // the "batchJobFormer". Maybe someday there will be a better way.
    guard
      let initial = try InitialStateComputer(
        options,
        jobsInPhases,
        outputFileMap,
        buildRecordInfo,
        maybeBuildRecord,
        self.reporter,
        driver.inputFiles,
        driver.fileSystem,
        showJobLifecycle: driver.showJobLifecycle,
        driver.diagnosticEngine)
        .compute(batchJobFormer: &driver)
    else {
      return nil
    }

    self.skippedCompileGroups = initial.skippedCompileGroups
    self.mandatoryJobsInOrder = initial.mandatoryJobsInOrder
    self.jobsAfterCompiles = jobsInPhases.afterCompiles
    self.moduleDependencyGraph = initial.graph
    self.driver = driver
  }
}

// MARK: - Initial State

extension IncrementalCompilationState {
  /// The initial state of an incremental compilation plan.
  @_spi(Testing) public struct InitialState {
    /// The dependency graph.
    ///
    /// In a status quo build, the dependency graph is derived from the state
    /// of the build record, which points to all files built in the prior build.
    /// When this information is combined with the output file map, swiftdeps
    /// files can be located and loaded into the graph.
    ///
    /// In a cross-module build, the dependency graph is derived from prior
    /// state that is serialized alongside the build record.
    let graph: ModuleDependencyGraph
    /// The set of compile jobs we can definitely skip given the state of the
    /// incremental dependency graph and the status of the input files for this
    /// incremental build.
    let skippedCompileGroups: [TypedVirtualPath: CompileJobGroup]
    /// All of the pre-compile or compilation job (groups) known to be required
    /// for the first wave to execute.
    let mandatoryJobsInOrder: [Job]
  }
}

extension Driver {
  /// Check various arguments to rule out incremental compilation if need be.
  static func shouldAttemptIncrementalCompilation(
    _ parsedOptions: inout ParsedOptions,
    diagnosticEngine: DiagnosticsEngine,
    compilerMode: CompilerMode
  ) -> Bool {
    guard parsedOptions.hasArgument(.incremental) else {
      return false
    }
    guard compilerMode.supportsIncrementalCompilation else {
      diagnosticEngine.emit(
        .remark_incremental_compilation_has_been_disabled(
          because: "it is not compatible with \(compilerMode)"))
      return false
    }
    guard !parsedOptions.hasArgument(.embedBitcode) else {
      diagnosticEngine.emit(
        .remark_incremental_compilation_has_been_disabled(
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
  fileprivate static var warning_incremental_requires_output_file_map: Diagnostic.Message {
    .warning("ignoring -incremental (currently requires an output file map)")
  }
  static var warning_incremental_requires_build_record_entry: Diagnostic.Message {
    .warning(
      "ignoring -incremental; " +
        "output file map has no master dependencies entry (\"\(FileType.swiftDeps)\" under \"\")"
    )
  }

  static let remarkDisabled = Diagnostic.Message.remark_incremental_compilation_has_been_disabled

  static func remark_incremental_compilation_has_been_disabled(because why: String) -> Diagnostic.Message {
    return .remark("Incremental compilation has been disabled: \(why)")
  }

  fileprivate static func remark_incremental_compilation(because why: String) -> Diagnostic.Message {
    .remark("Incremental compilation: \(why)")
  }

  fileprivate static var warning_could_not_write_dependency_graph: Diagnostic.Message {
    .warning("next compile won't be incremental; could not write dependency graph")
  }
}

// MARK: - Scheduling the 2nd wave
extension IncrementalCompilationState {
  /// Remember a job (group) that is before a compile or a compile itself.
  /// `job` just finished. Update state, and return the skipped compile job (groups) that are now known to be needed.
  /// If no more compiles are needed, return nil.
  /// Careful: job may not be primary.
  public func collectJobsDiscoveredToBeNeededAfterFinishing(
    job finishedJob: Job) throws -> [Job]? {
    return try self.confinementQueue.sync {
      // Find and deal with inputs that now need to be compiled
      let invalidatedInputs = collectInputsInvalidatedByRunning(finishedJob)
      assert(Set(invalidatedInputs).isDisjoint(with: finishedJob.primaryInputs),
             "Primaries should not overlap secondaries.")

      if let reporter = self.reporter {
        for input in invalidatedInputs {
          reporter.report(
            "Queuing because of dependencies discovered later:", input)
        }
      }
      return try getJobs(for: invalidatedInputs)
    }
  }

  /// Needed for API compatibility, `result` will be ignored
  public func collectJobsDiscoveredToBeNeededAfterFinishing(
    job finishedJob: Job, result: ProcessResult
  ) throws -> [Job]? {
    try collectJobsDiscoveredToBeNeededAfterFinishing(job: finishedJob)
  }

  /// After `job` finished find out which inputs must compiled that were not known to need compilation before
  private func collectInputsInvalidatedByRunning(_ job: Job)-> Set<TypedVirtualPath> {
    dispatchPrecondition(condition: .onQueue(self.confinementQueue))
    guard job.kind == .compile else {
      return Set<TypedVirtualPath>()
    }
    return job.primaryInputs.reduce(into: Set()) { invalidatedInputs, primaryInput in
      invalidatedInputs.formUnion(collectInputsInvalidated(byCompiling: primaryInput))
    }
    .subtracting(job.primaryInputs) // have already compiled these
  }

  private func collectInputsInvalidated(
    byCompiling input: TypedVirtualPath
  ) -> TransitivelyInvalidatedInputSet {
    dispatchPrecondition(condition: .onQueue(self.confinementQueue))
    if let found = moduleDependencyGraph.collectInputsRequiringCompilation(byCompiling: input) {
      return found
    }
    self.reporter?.report(
      "Failed to read some dependencies source; compiling everything", input)
    return TransitivelyInvalidatedInputSet(skippedCompileGroups.keys)
  }

  /// Find the jobs that now must be run that were not originally known to be needed.
  private func getJobs(
    for invalidatedInputs: Set<TypedVirtualPath>
  ) throws -> [Job] {
    dispatchPrecondition(condition: .onQueue(self.confinementQueue))
    let unbatched = invalidatedInputs.flatMap { input -> [Job] in
      if let group = skippedCompileGroups.removeValue(forKey: input) {
        let primaryInputs = group.compileJob.primaryInputs
        assert(primaryInputs.count == 1)
        assert(primaryInputs[0] == input)
        self.reporter?.report("Scheduling invalidated", input)
        return group.allJobs()
      }
      else {
        self.reporter?.report("Tried to schedule invalidated input again", input)
        return []
      }
    }
    return try driver.formBatchedJobs(unbatched, showJobLifecycle: driver.showJobLifecycle)
  }
}

// MARK: - After the build
extension IncrementalCompilationState {
  var skippedCompilationInputs: Set<TypedVirtualPath> {
    return self.confinementQueue.sync {
      Set(skippedCompileGroups.keys)
    }
  }
  public var skippedJobs: [Job] {
    return self.confinementQueue.sync {
      skippedCompileGroups.values
        .sorted {$0.primaryInput.file.name < $1.primaryInput.file.name}
        .flatMap {$0.allJobs()}
    }
  }
}

// MARK: - Remarks

extension IncrementalCompilationState {
  /// A type that manages the reporting of remarks about the state of the
  /// incremental build.
  public struct Reporter {
    let diagnosticEngine: DiagnosticsEngine
    let outputFileMap: OutputFileMap?

    /// Report a remark with the given message.
    ///
    /// The `path` parameter is used specifically for reporting the state of
    /// compile jobs that are transiting through the incremental build pipeline.
    /// If provided, and valid entries in the output file map are provided,
    /// the reporter will format a message of the form
    ///
    /// ```
    /// <message> {compile: <output> <= <input>}
    /// ```
    ///
    /// Which mirrors the behavior of the legacy driver.
    ///
    /// - Parameters:
    ///   - message: The message to emit in the remark.
    ///   - path: If non-nil, the path of some file. If the output for an incremental job, will print out the
    ///           source and object files.
    func report(_ message: String, _ pathIfGiven: TypedVirtualPath?) {
       guard let path = pathIfGiven,
            let outputFileMap = outputFileMap,
            let input = path.type == .swift ? path.file : outputFileMap.getInput(outputFile: path.file)
      else {
        report(message, pathIfGiven?.file)
        return
      }
      let output = outputFileMap.getOutput(inputFile: path.fileHandle, outputType: .object)
      let compiling = " {compile: \(VirtualPath.lookup(output).basename) <= \(input.basename)}"
      diagnosticEngine.emit(.remark_incremental_compilation(because: "\(message) \(compiling)"))
    }

    /// Entry point for a simple path, won't print the compile job, path could be anything.
    func report(_ message: String, _ path: VirtualPath?) {
      guard let path = path
      else {
        report(message)
        diagnosticEngine.emit(.remark_incremental_compilation(because: message))
        return
      }
      diagnosticEngine.emit(.remark_incremental_compilation(because: "\(message) '\(path.name)'"))
    }

    /// Entry point if no path.
    func report(_ message: String) {
      diagnosticEngine.emit(.remark_incremental_compilation(because: message))
    }


    // Emits a remark indicating incremental compilation has been disabled.
    func reportDisablingIncrementalBuild(_ why: String) {
      report("Disabling incremental build: \(why)")
    }

    // Emits a remark indicating incremental compilation has been disabled.
    //
    // FIXME: This entrypoint exists for compatiblity with the legacy driver.
    // This message is not necessary, and we should migrate the tests.
    func reportIncrementalCompilationHasBeenDisabled(_ why: String) {
      report("Incremental compilation has been disabled, \(why)")
    }
  }
}

// MARK: - Remarks

extension IncrementalCompilationState {
  /// Options that control the behavior of various aspects of the
  /// incremental build.
  public struct Options: OptionSet {
    public var rawValue: UInt8

    public init(rawValue: UInt8) {
      self.rawValue = rawValue
    }

    /// Be maximally conservative about rebuilding dependents of dirtied files
    /// during the incremental build. Dependent files are always scheduled to
    /// rebuild.
    public static let alwaysRebuildDependents                = Options(rawValue: 1 << 0)
    /// Print incremental build decisions as remarks.
    public static let showIncremental                        = Options(rawValue: 1 << 1)
    /// After integrating each source file dependency graph into the driver's
    /// module dependency graph, dump a dot file to the current working
    /// directory showing the state of the driver's dependency graph.
    ///
    /// FIXME: This option is not yet implemented.
    public static let emitDependencyDotFileAfterEveryImport  = Options(rawValue: 1 << 2)
    /// After integrating each source file dependency graph, verifies the
    /// integrity of the driver's dependency graph and aborts if any errors
    /// are detected.
    public static let verifyDependencyGraphAfterEveryImport  = Options(rawValue: 1 << 3)
    /// Enables the cross-module incremental build infrastructure.
    ///
    /// FIXME: This option is transitory. We intend to make this the
    /// default behavior. This option should flip to a "disable" bit after that.
    public static let enableCrossModuleIncrementalBuild      = Options(rawValue: 1 << 4)
    /// Enables an optimized form of start-up for the incremental build state
    /// that reads the dependency graph from a serialized format on disk instead
    /// of reading O(N) swiftdeps files.
    public static let readPriorsFromModuleDependencyGraph    = Options(rawValue: 1 << 5)
  }
}

// MARK: - Serialization

extension IncrementalCompilationState {
  @_spi(Testing) public func writeDependencyGraph() {
    // If the cross-module build is not enabled, the status quo dictates we
    // not emit this file.
    guard moduleDependencyGraph.info.isCrossModuleIncrementalBuildEnabled else {
      return
    }

    guard
      let recordInfo = self.driver.buildRecordInfo
    else {
      self.driver.diagnosticEngine.emit(
        .warning_could_not_write_dependency_graph)
      return
    }
    self.moduleDependencyGraph.write(to: recordInfo.dependencyGraphPath,
                                     on: self.driver.fileSystem,
                                     compilerVersion: recordInfo.actualSwiftVersion)
  }
}

// MARK: - OutputFileMap
extension OutputFileMap {
  func onlySourceFilesHaveSwiftDeps() -> Bool {
    let nonSourceFilesWithSwiftDeps = entries.compactMap { input, outputs in
      VirtualPath.lookup(input).extension != FileType.swift.rawValue &&
        input.description != "." &&
        outputs.keys.contains(.swiftDeps)
        ? input
        : nil
    }
    if let f = nonSourceFilesWithSwiftDeps.first {
      fatalError("nonSource \(f) has swiftDeps \(entries[f]![.swiftDeps]!)")
    }
    return nonSourceFilesWithSwiftDeps.isEmpty
  }
}

// MARK: SourceFiles
@_spi(Testing) public struct SourceFiles {
  let currentInOrder: [TypedVirtualPath]
  private let previous: Set<VirtualPath.Handle>
  let disappeared: [VirtualPath.Handle]

  init(inputFiles: [TypedVirtualPath], buildRecord: BuildRecord?) {
    self.currentInOrder = inputFiles.filter {$0.type == .swift}
    let currentSet = Set(currentInOrder.map {$0.fileHandle} )
    self.previous = buildRecord.map {
      Set($0.inputInfos.keys)
    } ?? Set()

    self.disappeared = previous.filter {!currentSet.contains($0)}
  }

  func isANewInput(_ file: VirtualPath.Handle) -> Bool {
    !previous.contains(file)
  }
}
