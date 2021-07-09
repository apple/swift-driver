//===--------------- BuildRecordInfo.swift --------------------------------===//
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

import Foundation
import TSCBasic
import SwiftOptions

/// Holds information required to read and write the build record (aka
/// compilation record).
///
/// This info is always written, but only read for incremental compilation.
@_spi(Testing) public final class BuildRecordInfo {
  /// A pair of a `Job` and the `ProcessResult` corresponding to the outcome of
  /// its execution during this compilation session.
  struct JobResult {
    /// The job that was executed.
    var job: Job
    /// The result of executing the associated `job`.
    var result: ProcessResult

    init(_ j: Job, _ result: ProcessResult) {
      self.job = j
      self.result = result
    }
  }

  let buildRecordPath: VirtualPath
  let fileSystem: FileSystem
  let currentArgsHash: String
  @_spi(Testing) public let actualSwiftVersion: String
  let timeBeforeFirstJob: Date
  let diagnosticEngine: DiagnosticsEngine
  let compilationInputModificationDates: [TypedVirtualPath: Date]

  private var finishedJobResults = [JobResult]()
  // A confinement queue that protects concurrent access to the
  // `finishedJobResults` array.
  // FIXME: Use an actor when possible.
  private let confinementQueue = DispatchQueue(label: "com.apple.swift-driver.jobresults")

  @_spi(Testing) public init(
    buildRecordPath: VirtualPath,
    fileSystem: FileSystem,
    currentArgsHash: String,
    actualSwiftVersion: String,
    timeBeforeFirstJob: Date,
    diagnosticEngine: DiagnosticsEngine,
    compilationInputModificationDates: [TypedVirtualPath: Date])
  {
    self.buildRecordPath = buildRecordPath
    self.fileSystem = fileSystem
    self.currentArgsHash = currentArgsHash
    self.actualSwiftVersion = actualSwiftVersion
    self.timeBeforeFirstJob = timeBeforeFirstJob
    self.diagnosticEngine = diagnosticEngine
    self.compilationInputModificationDates = compilationInputModificationDates
  }


  convenience init?(
    actualSwiftVersion: String,
    compilerOutputType: FileType?,
    workingDirectory: AbsolutePath?,
    diagnosticEngine: DiagnosticsEngine,
    fileSystem: FileSystem,
    moduleOutputInfo: ModuleOutputInfo,
    outputFileMap: OutputFileMap?,
    incremental: Bool,
    parsedOptions: ParsedOptions,
    recordedInputModificationDates: [TypedVirtualPath: Date]
  ) {
    // Cannot write a buildRecord without a path.
    guard let buildRecordPath = Self.computeBuildRecordPath(
            outputFileMap: outputFileMap,
            incremental: incremental,
            compilerOutputType: compilerOutputType,
            workingDirectory: workingDirectory,
            diagnosticEngine: diagnosticEngine)
    else {
      return nil
    }
    let currentArgsHash = Self.computeArgsHash(parsedOptions)
    let compilationInputModificationDates =
      recordedInputModificationDates.filter { input, _ in
        input.type.isPartOfSwiftCompilation
      }

    self.init(
      buildRecordPath: buildRecordPath,
      fileSystem: fileSystem,
      currentArgsHash: currentArgsHash,
      actualSwiftVersion: actualSwiftVersion,
      timeBeforeFirstJob: Date(),
      diagnosticEngine: diagnosticEngine,
      compilationInputModificationDates: compilationInputModificationDates)
   }

  private static func computeArgsHash(_ parsedOptionsArg: ParsedOptions
  ) -> String {
    var parsedOptions = parsedOptionsArg
    let hashInput = parsedOptions
      .filter { $0.option.affectsIncrementalBuild && $0.option.kind != .input}
      .map { $0.option.spelling }
      .sorted()
      .joined()
    #if os(macOS)
    if #available(macOS 10.15, iOS 13, *) {
      return CryptoKitSHA256().hash(hashInput).hexadecimalRepresentation
    } else {
      return SHA256().hash(hashInput).hexadecimalRepresentation
    }
    #else
    return SHA256().hash(hashInput).hexadecimalRepresentation
    #endif
  }

  /// Determine the input and output path for the build record
  private static func computeBuildRecordPath(
    outputFileMap: OutputFileMap?,
    incremental: Bool,
    compilerOutputType: FileType?,
    workingDirectory: AbsolutePath?,
    diagnosticEngine: DiagnosticsEngine
  ) -> VirtualPath? {
    // FIXME: This should work without an output file map. We should have
    // another way to specify a build record and where to put intermediates.
    guard let ofm = outputFileMap else {
      return nil
    }
    guard let partialBuildRecordPath =
            ofm.existingOutputForSingleInput(outputType: .swiftDeps)
    else {
      if incremental {
        diagnosticEngine.emit(.warning_incremental_requires_build_record_entry)
      }
      return nil
    }
    return workingDirectory
      .map(VirtualPath.lookup(partialBuildRecordPath).resolvedRelativePath(base:))
      ?? VirtualPath.lookup(partialBuildRecordPath)
  }

  /// Write out the build record.
  ///
  /// - Parameters:
  ///   - jobs: All compilation jobs formed during this build.
  ///   - skippedInputs: All primary inputs that were not compiled because the
  ///                    incremental build plan determined they could be
  ///                    skipped.
  func writeBuildRecord(_ jobs: [Job], _ skippedInputs: Set<TypedVirtualPath>?) {
    guard let absPath = buildRecordPath.absolutePath else {
      diagnosticEngine.emit(
        .warning_could_not_write_build_record_not_absolutePath(buildRecordPath))
      return
    }
    preservePreviousBuildRecord(absPath)

    let buildRecord = self.confinementQueue.sync {
      BuildRecord(
        jobs: jobs,
        finishedJobResults: finishedJobResults,
        skippedInputs: skippedInputs,
        compilationInputModificationDates: compilationInputModificationDates,
        actualSwiftVersion: actualSwiftVersion,
        argsHash: currentArgsHash,
        timeBeforeFirstJob: timeBeforeFirstJob,
        timeAfterLastJob: Date())
    }

    guard let contents = buildRecord.encode(currentArgsHash: currentArgsHash,
                                            diagnosticEngine: diagnosticEngine)
    else {
      return
    }
    do {
      try fileSystem.writeFileContents(absPath,
                                       bytes: ByteString(encodingAsUTF8: contents))
    } catch {
      diagnosticEngine.emit(.warning_could_not_write_build_record(absPath))
    }
  }

  func removeBuildRecord() {
    guard let absPath = buildRecordPath.absolutePath else {
      return
    }
    try? fileSystem.removeFileTree(absPath)
  }

  /// Before writing to the dependencies file path, preserve any previous file
  /// that may have been there. No error handling -- this is just a nicety, it
  /// doesn't matter if it fails.
  /// Added for the sake of compatibility with the legacy driver.
  private func preservePreviousBuildRecord(_ oldPath: AbsolutePath) {
    let newPath = oldPath.withTilde()
    try? fileSystem.move(from: oldPath, to: newPath)
  }


// TODO: Incremental too many names, buildRecord BuildRecord outofdatemap
  func populateOutOfDateBuildRecord(
    inputFiles: [TypedVirtualPath],
    reporter: IncrementalCompilationState.Reporter?
  ) -> BuildRecord? {
    let contents: String
    do {
      contents = try fileSystem.readFileContents(buildRecordPath).cString
     } catch {
      reporter?.report("Incremental compilation could not read build record at ", buildRecordPath)
      reporter?.reportDisablingIncrementalBuild("could not read build record")
      return nil
    }
    func failedToReadOutOfDateMap(_ reason: String? = nil) {
      let why = "malformed build record file\(reason.map {" " + $0} ?? "")"
      reporter?.report(
        "Incremental compilation has been disabled due to \(why)", buildRecordPath)
      reporter?.reportDisablingIncrementalBuild(why)
    }
    guard let outOfDateBuildRecord = BuildRecord(contents: contents,
                                                 failedToReadOutOfDateMap: failedToReadOutOfDateMap)
    else {
      return nil
    }
    guard actualSwiftVersion == outOfDateBuildRecord.swiftVersion
    else {
      let why = "compiler version mismatch. Compiling with: \(actualSwiftVersion). Previously compiled with: \(outOfDateBuildRecord.swiftVersion)"
      // mimic legacy
      reporter?.reportIncrementalCompilationHasBeenDisabled("due to a " + why)
      reporter?.reportDisablingIncrementalBuild(why)
      return nil
    }
    guard outOfDateBuildRecord.argsHash.map({ $0 == currentArgsHash }) ?? true else {
      let why = "different arguments were passed to the compiler"
      // mimic legacy
      reporter?.reportIncrementalCompilationHasBeenDisabled("because " + why)
      reporter?.reportDisablingIncrementalBuild(why)
      return nil
    }
    return outOfDateBuildRecord
  }

  func jobFinished(job: Job, result: ProcessResult) {
    self.confinementQueue.sync {
      finishedJobResults.append(JobResult(job, result))
    }
  }

  /// A build-record-relative path to the location of a serialized copy of the
  /// driver's dependency graph.
  ///
  /// FIXME: This is a little ridiculous. We could probably just replace the
  /// build record outright with a serialized format.
  var dependencyGraphPath: VirtualPath {
    let filename = buildRecordPath.basenameWithoutExt
    return buildRecordPath
      .parentDirectory
      .appending(component: filename + ".priors")
  }

  /// Directory to emit dot files into
  var dotFileDirectory: VirtualPath {
    buildRecordPath.parentDirectory
  }
}

fileprivate extension AbsolutePath {
  func withTilde() -> Self {
    parentDirectory.appending(component: basename + "~")
  }
}
