//===--- MultiJobExecutor.swift - Builtin DriverExecutor implementation ---===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SwiftDriver
import TSCBasic
import Foundation

public final class SwiftDriverExecutor: DriverExecutor {
  let diagnosticsEngine: DiagnosticsEngine
  let processSet: ProcessSet
  let fileSystem: FileSystem
  public let resolver: ArgsResolver
  let env: [String: String]

  public init(diagnosticsEngine: DiagnosticsEngine,
              processSet: ProcessSet,
              fileSystem: FileSystem,
              env: [String: String]) throws {
    self.diagnosticsEngine = diagnosticsEngine
    self.processSet = processSet
    self.fileSystem = fileSystem
    self.env = env
    self.resolver = try ArgsResolver(fileSystem: fileSystem)
  }

  public func execute(job: Job,
                      forceResponseFiles: Bool = false,
                      recordedInputModificationDates: [TypedVirtualPath: Date] = [:]) throws -> ProcessResult {
    let arguments: [String] = try resolver.resolveArgumentList(for: job,
                                                               forceResponseFiles: forceResponseFiles)

    try job.verifyInputsNotModified(since: recordedInputModificationDates,
                                    fileSystem: fileSystem)

    if job.requiresInPlaceExecution {
      for (envVar, value) in job.extraEnvironment {
        try ProcessEnv.setVar(envVar, value: value)
      }

      try exec(path: arguments[0], args: arguments)
      fatalError("unreachable, exec always throws on failure")
    } else {
      var childEnv = env
      childEnv.merge(job.extraEnvironment, uniquingKeysWith: { (_, new) in new })

      let process = try Process.launchProcess(arguments: arguments, env: childEnv)
      return try process.waitUntilExit()
    }
  }

  public func execute(workload: DriverExecutorWorkload,
                      delegate: JobExecutionDelegate,
                      numParallelJobs: Int = 1,
                      forceResponseFiles: Bool = false,
                      skipProcessExecution: Bool,
                      recordedInputModificationDates: [TypedVirtualPath: Date] = [:]
  ) throws {
    let llbuildExecutor = MultiJobExecutor(
      workload: workload,
      resolver: resolver,
      executorDelegate: delegate,
      diagnosticsEngine: diagnosticsEngine,
      numParallelJobs: numParallelJobs,
      processSet: processSet,
      forceResponseFiles: forceResponseFiles,
      recordedInputModificationDates: recordedInputModificationDates,
      processType: skipProcessExecution ? DummyProcess.self : TSCBasic.Process.self)
    try llbuildExecutor.execute(env: env, fileSystem: fileSystem)
  }

  @discardableResult
  public func checkNonZeroExit(args: String..., environment: [String: String] = ProcessEnv.vars) throws -> String {
    return try Process.checkNonZeroExit(arguments: args, environment: environment)
  }

  public func description(of job: Job, forceResponseFiles: Bool) throws -> String {
    let (args, usedResponseFile) = try resolver.resolveArgumentList(for: job, forceResponseFiles: forceResponseFiles)
    var result = args.map { $0.spm_shellEscaped() }.joined(separator: " ")

    if usedResponseFile {
      // Print the response file arguments as a comment.
      result += " # \(job.commandLine.joinedUnresolvedArguments)"
    }

    if !job.extraEnvironment.isEmpty {
      result += " #"
      for (envVar, val) in job.extraEnvironment {
        result += " \(envVar)=\(val)"
      }
    }
    return result
  }
}

/// C++ driver uses fake processes when skipping driver execution, instead of just skipping execution entirely.
/// This distinction is important, because it allows parsable output to be emitted for the jobs.
private struct DummyProcess: ProcessProtocol {
  private static var nextProcessID: TSCBasic.Process.ProcessID = 0

  let processID: TSCBasic.Process.ProcessID
  private let arguments: [String]
  private let env: [String: String]

  private init(arguments: [String], env: [String: String]) {
    processID = Self.nextProcessID
    Self.nextProcessID += 1

    self.arguments = arguments
    self.env = env
  }

  func waitUntilExit() throws -> ProcessResult {
    return .init(arguments: arguments,
                 environment: env,
                 exitStatus: .terminated(code: 0),
                 output: .success([UInt8]("Output placeholder\n".utf8CString.map { UInt8($0) })),
                 stderrOutput: .success([UInt8]("Error placeholder\n".utf8CString.map { UInt8($0) })))
  }

  static func launchProcess(arguments: [String], env: [String: String]) throws -> DummyProcess {
    return DummyProcess(arguments: arguments, env: env)
  }
}
