//===--------------- DriverExecutor.swift - Swift Driver Executor----------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import TSCBasic
import Foundation

public protocol DriverExecutor {
  var resolver: ArgsResolver { get }

  /// Execute a single job and capture the output.
  @discardableResult
  func execute(job: Job,
               forceResponseFiles: Bool,
               recordedInputModificationDates: [TypedVirtualPath: Date]) throws -> ProcessResult
  
  /// Execute multiple jobs, tracking job status using the provided execution delegate.
  /// Pass in the `IncrementalCompilationState` to allow for incremental compilation.
  func execute(workload: DriverExecutorWorkload,
               delegate: JobExecutionDelegate,
               numParallelJobs: Int,
               forceResponseFiles: Bool,
               skipProcessExecution: Bool,
               recordedInputModificationDates: [TypedVirtualPath: Date]
  ) throws
  
  // FIXME: Stub for SPM
  func execute(workload: DriverExecutorWorkload,
               delegate: JobExecutionDelegate,
               numParallelJobs: Int,
               forceResponseFiles: Bool,
               recordedInputModificationDates: [TypedVirtualPath: Date]
  ) throws

  /// Execute multiple jobs, tracking job status using the provided execution delegate.
  func execute(jobs: [Job],
               delegate: JobExecutionDelegate,
               numParallelJobs: Int,
               forceResponseFiles: Bool,
               recordedInputModificationDates: [TypedVirtualPath: Date]
  ) throws

  /// Launch a process with the given command line and report the result.
  @discardableResult
  func checkNonZeroExit(args: String..., environment: [String: String]) throws -> String

  /// Returns a textual description of the job as it would be run by the executor.
  func description(of job: Job, forceResponseFiles: Bool) throws -> String
}

public struct DriverExecutorWorkload {
  public let continueBuildingAfterErrors: Bool
  public enum Kind {
    case all([Job])
    case incremental(IncrementalCompilationState)
  }
  public let kind: Kind

  public init(_ allJobs: [Job],
       _ incrementalCompilationState: IncrementalCompilationState?,
       continueBuildingAfterErrors: Bool
  ) {
      self.continueBuildingAfterErrors = continueBuildingAfterErrors
      self.kind = incrementalCompilationState
        .map {.incremental($0)}
        ?? .all(allJobs)
  }

  static public func all(_ jobs: [Job]) -> Self {
    .init(jobs, nil, continueBuildingAfterErrors: false)
  }
}

enum JobExecutionError: Error {
  case jobFailedWithNonzeroExitCode(Int, String)
  case failedToReadJobOutput
  // A way to pass more information to the catch point
  case decodingError(DecodingError, Data, ProcessResult)
}

extension DriverExecutor {
  func execute<T: Decodable>(job: Job,
                             capturingJSONOutputAs outputType: T.Type,
                             forceResponseFiles: Bool,
                             recordedInputModificationDates: [TypedVirtualPath: Date]) throws -> T {
    let result = try execute(job: job,
                             forceResponseFiles: forceResponseFiles,
                             recordedInputModificationDates: recordedInputModificationDates)
    
    if (result.exitStatus != .terminated(code: EXIT_SUCCESS)) {
      let returnCode = Self.computeReturnCode(exitStatus: result.exitStatus)
      throw JobExecutionError.jobFailedWithNonzeroExitCode(returnCode, try result.utf8stderrOutput())
    }
    guard let outputData = try? Data(result.utf8Output().utf8) else {
      throw JobExecutionError.failedToReadJobOutput
    }

    do {
      return try JSONDecoder().decode(outputType, from: outputData)
    } catch let err as DecodingError {
      throw JobExecutionError.decodingError(err, outputData, result)
    }
  }

  public func execute(
    jobs: [Job],
    delegate: JobExecutionDelegate,
    numParallelJobs: Int,
    forceResponseFiles: Bool,
    recordedInputModificationDates: [TypedVirtualPath: Date]
  ) throws {
    try execute(
      workload: .all(jobs),
      delegate: delegate,
      numParallelJobs: numParallelJobs,
      forceResponseFiles: forceResponseFiles,
      recordedInputModificationDates: recordedInputModificationDates)
  }
  
  static func computeReturnCode(exitStatus: ProcessResult.ExitStatus) -> Int {
    var returnCode: Int
    switch exitStatus {
      case .terminated(let code):
        returnCode = Int(code)
      #if !os(Windows)
      case .signalled(let signal):
        returnCode = Int(signal)
      #endif
    }
    return returnCode
  }
}

// FIXME: stubs to prevent breaking SPM build. If none of these are implemented they will infinite loop until stack overflow.
// These should be cleaned up quickly.
extension DriverExecutor {
  public func execute(
    workload: DriverExecutorWorkload,
    delegate: JobExecutionDelegate,
    numParallelJobs: Int,
    forceResponseFiles: Bool,
    recordedInputModificationDates: [TypedVirtualPath: Date]
  ) throws {
    return try execute(
      workload: workload,
      delegate: delegate,
      numParallelJobs: numParallelJobs,
      forceResponseFiles: forceResponseFiles,
      skipProcessExecution: false,
      recordedInputModificationDates: recordedInputModificationDates)
  }
  
  public func execute(
    workload: DriverExecutorWorkload,
    delegate: JobExecutionDelegate,
    numParallelJobs: Int,
    forceResponseFiles: Bool,
    skipProcessExecution: Bool,
    recordedInputModificationDates: [TypedVirtualPath: Date]
  ) throws {
    return try execute(
      workload: workload,
      delegate: delegate,
      numParallelJobs: numParallelJobs,
      forceResponseFiles: forceResponseFiles,
      recordedInputModificationDates: recordedInputModificationDates)
  }
}

public protocol JobExecutionDelegate {
  /// Called when a job starts executing.
  func jobStarted(job: Job, arguments: [String], pid: Int)
  
  /// Called when a job finished.
  func jobFinished(job: Job, result: ProcessResult, pid: Int)

  /// Called when a job is skipped.
  func jobSkipped(job: Job)
}
