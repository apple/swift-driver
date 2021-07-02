//===--------------- ParsableMessageTests.swift - Swift Parsable Output ---===//
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
import XCTest
import Foundation
import TSCBasic
import TSCUtility

@_spi(Testing) import SwiftDriver

final class ParsableMessageTests: XCTestCase {
  private func withHijackedBufferedErrorStream(
    in path: AbsolutePath,
    prefix: String = "dummy_error_stream",
    _ body: (AbsolutePath) throws -> ()
  ) throws {
    // Replace the error stream with one we capture here.
    let errorStream = stderrStream
    let errorOutputFile = path.appending(component: prefix)
    TSCBasic.stderrStream =
      try! ThreadSafeOutputByteStream(LocalFileOutputByteStream(errorOutputFile))
    try body(errorOutputFile)
    TSCBasic.stderrStream.flush()
    // Restore the error stream to what it was
    TSCBasic.stderrStream = errorStream
  }

  func testBeganMessage() throws {
    let message = BeganMessage(
      pid: 1,
      realPid: 1,
      inputs: ["/path/to/foo.swift"],
      outputs: [
      .init(path: "/path/to/foo.o", type: "object")
      ],
      commandExecutable: "/path/to/swiftc",
      commandArguments: ["-frontend", "compile"]
    )

    let beganMessage = ParsableMessage(name: "compile", kind: .began(message))

    let encoded = try beganMessage.toJSON()
    let string = String(data: encoded, encoding: .utf8)!

    XCTAssertEqual(string, """
      {
        "command_arguments" : [
          "-frontend",
          "compile"
        ],
        "command_executable" : "\\/path\\/to\\/swiftc",
        "inputs" : [
          "\\/path\\/to\\/foo.swift"
        ],
        "kind" : "began",
        "name" : "compile",
        "outputs" : [
          {
            "path" : "\\/path\\/to\\/foo.o",
            "type" : "object"
          }
        ],
        "pid" : 1,
        "process" : {
          "real_pid" : 1
        }
      }
      """)
  }

  func testFinishedMessage() throws {
    let message = FinishedMessage(exitStatus: 1, output: "hello", pid: 1, realPid: 1)
    let finishedMessage = ParsableMessage(name: "compile", kind: .finished(message))
    let encoded = try finishedMessage.toJSON()
    let string = String(data: encoded, encoding: .utf8)!

    XCTAssertEqual(string, """
    {
      "exit-status" : 1,
      "kind" : "finished",
      "name" : "compile",
      "output" : "hello",
      "pid" : 1,
      "process" : {
        "real_pid" : 1
      }
    }
    """)
  }

  func testSignalledMessage() throws {
    let message = SignalledMessage(pid: 2, realPid: 2, output: "sig",
                                   errorMessage: "err", signal: 3)
    let signalledMessage = ParsableMessage(name: "compile", kind: .signalled(message))
    let encoded = try signalledMessage.toJSON()
    let string = String(data: encoded, encoding: .utf8)!

    XCTAssertEqual(string, """
    {
      "error-message" : "err",
      "kind" : "signalled",
      "name" : "compile",
      "output" : "sig",
      "pid" : 2,
      "process" : {
        "real_pid" : 2
      },
      "signal" : 3
    }
    """)
  }

  func testBeganBatchMessages() throws {
    do {
      try withTemporaryDirectory { path in
        try withHijackedBufferedErrorStream(in: path) { errorBuffer in
          let resolver = try ArgsResolver(fileSystem: localFileSystem)
          var driver = try Driver(args: ["swiftc", "-o", "test.o",
                                         "main.swift", "test1.swift", "test2.swift",
                                         "-enable-batch-mode", "-driver-batch-count", "1",
                                         "-working-directory", "/WorkDir"])
          let jobs = try driver.planBuild()
          let compileJob = jobs[0]
          let args : [String] = try resolver.resolveArgumentList(for: compileJob, forceResponseFiles: false)
          let toolDelegate = ToolExecutionDelegate(mode: .parsableOutput,
                                                   buildRecordInfo: nil,
                                                   incrementalCompilationState: nil,
                                                   showJobLifecycle: false,
                                                   argsResolver: resolver,
                                                   diagnosticEngine: DiagnosticsEngine())

          // Emit the began messages and examine the output
          toolDelegate.jobStarted(job: compileJob, arguments: args, pid: 42)
          let errorOutput = try localFileSystem.readFileContents(errorBuffer).description

          // There were 3 messages emitted
          XCTAssertEqual(errorOutput.components(separatedBy:
          """
            "kind" : "began",
            "name" : "compile",
          """).count - 1, 3)

          /// One per primary
          XCTAssertTrue(errorOutput.contains(
          """
            "pid" : -1000,
          """))
          XCTAssertTrue(errorOutput.contains(
          """
            \"inputs\" : [
              \"\\/WorkDir\\/main.swift\"
            ],
          """))
          XCTAssertTrue(errorOutput.contains(
          """
            "pid" : -1001,
          """))
          XCTAssertTrue(errorOutput.contains(
          """
            \"inputs\" : [
              \"\\/WorkDir\\/test1.swift\"
            ],
          """))
          XCTAssertTrue(errorOutput.contains(
          """
            "pid" : -1002,
          """))
          XCTAssertTrue(errorOutput.contains(
          """
            \"inputs\" : [
              \"\\/WorkDir\\/test2.swift\"
            ],
          """))

          /// Real PID appeared in every message
          XCTAssertEqual(errorOutput.components(separatedBy:
          """
            \"process\" : {
              \"real_pid\" : 42
            }
          """).count - 1, 3)
        }
      }
    }
  }

  func testFinishedBatchMessages() throws {
    do {
      try withTemporaryDirectory { path in
        // Take over the error stream just to prevent it being printed in test runs
        var args: [String]?
        var compileJob: Job?
        var toolDelegate: ToolExecutionDelegate?
        try withHijackedBufferedErrorStream(in: path) { errorBuffer in
          let resolver = try ArgsResolver(fileSystem: localFileSystem)
          var driver = try Driver(args: ["swiftc", "-o", "test.o",
                                         "main.swift", "test1.swift", "test2.swift",
                                         "-enable-batch-mode", "-driver-batch-count", "1",
                                         "-working-directory", "/WorkDir"])
          let jobs = try driver.planBuild()
          compileJob = jobs[0]
          args = try resolver.resolveArgumentList(for: compileJob!, forceResponseFiles: false)
          toolDelegate = ToolExecutionDelegate(mode: .parsableOutput,
                                               buildRecordInfo: nil,
                                               incrementalCompilationState: nil,
                                               showJobLifecycle: false,
                                               argsResolver: resolver,
                                               diagnosticEngine: DiagnosticsEngine())

          // First emit the began messages
          toolDelegate!.jobStarted(job: compileJob!, arguments: args!, pid: 42)
        }
        // Now hijack the error stream and emit finished messages
        try withHijackedBufferedErrorStream(in: path) { errorBuffer in
          let resultSuccess = ProcessResult(arguments: args!,
                                            environment: ProcessEnv.vars,
                                            exitStatus: ProcessResult.ExitStatus.terminated(code: 0),
                                            output: Result.success([]),
                                            stderrOutput: Result.success([]))
          // Emit the finished messages and examine the output
          toolDelegate!.jobFinished(job: compileJob!, result: resultSuccess, pid: 42)
          let errorOutput = try localFileSystem.readFileContents(errorBuffer).description
          XCTAssertTrue(errorOutput.contains(
          """
          {
            \"exit-status\" : 0,
            \"kind\" : \"finished\",
            \"name\" : \"compile\",
            \"pid\" : -1000,
            \"process\" : {
              \"real_pid\" : 42
            }
          }
          """))
          XCTAssertTrue(errorOutput.contains(
          """
          {
            \"exit-status\" : 0,
            \"kind\" : \"finished\",
            \"name\" : \"compile\",
            \"pid\" : -1001,
            \"process\" : {
              \"real_pid\" : 42
            }
          }
          """))
          XCTAssertTrue(errorOutput.contains(
          """
          {
            \"exit-status\" : 0,
            \"kind\" : \"finished\",
            \"name\" : \"compile\",
            \"pid\" : -1002,
            \"process\" : {
              \"real_pid\" : 42
            }
          }
          """))
        }
      }
    }
  }

  func testSignalledBatchMessages() throws {
    do {
      try withTemporaryDirectory { path in
        // Take over the error stream just to prevent it being printed in test runs
        var args: [String]?
        var compileJob: Job?
        var toolDelegate: ToolExecutionDelegate?
        try withHijackedBufferedErrorStream(in: path) { errorBuffer in
          let resolver = try ArgsResolver(fileSystem: localFileSystem)
          var driver = try Driver(args: ["swiftc", "-o", "test.o",
                                         "main.swift", "test1.swift", "test2.swift",
                                         "-enable-batch-mode", "-driver-batch-count", "1",
                                         "-working-directory", "/WorkDir"])
          let jobs = try driver.planBuild()
          compileJob = jobs[0]
          args  = try resolver.resolveArgumentList(for: compileJob!,
                                                   forceResponseFiles: false)
          toolDelegate = ToolExecutionDelegate(mode: .parsableOutput,
                                               buildRecordInfo: nil,
                                               incrementalCompilationState: nil,
                                               showJobLifecycle: false,
                                               argsResolver: resolver,
                                               diagnosticEngine: DiagnosticsEngine())

          // First emit the began messages
          toolDelegate!.jobStarted(job: compileJob!, arguments: args!, pid: 42)
        }
        // Now hijack the error stream and emit finished messages
        try withHijackedBufferedErrorStream(in: path) { errorBuffer in
          let resultSignalled = ProcessResult(arguments: args!,
                                              environment: ProcessEnv.vars,
                                              exitStatus: ProcessResult.ExitStatus.signalled(signal: 9),
                                              output: Result.success([]),
                                              stderrOutput: Result.success([]))
          // First emit the began messages
          toolDelegate!.jobFinished(job: compileJob!, result: resultSignalled, pid: 42)
          let errorOutput = try localFileSystem.readFileContents(errorBuffer).description
          XCTAssertTrue(errorOutput.contains(
          """
            \"kind\" : \"signalled\",
            \"name\" : \"compile\",
            \"pid\" : -1000,
            \"process\" : {
              \"real_pid\" : 42
            },
            \"signal\" : 9
          }
          """))
          XCTAssertTrue(errorOutput.contains(
          """
            \"kind\" : \"signalled\",
            \"name\" : \"compile\",
            \"pid\" : -1001,
            \"process\" : {
              \"real_pid\" : 42
            },
            \"signal\" : 9
          }
          """))
          XCTAssertTrue(errorOutput.contains(
          """
            \"kind\" : \"signalled\",
            \"name\" : \"compile\",
            \"pid\" : -1002,
            \"process\" : {
              \"real_pid\" : 42
            },
            \"signal\" : 9
          }
          """))
        }
      }
    }
  }

  func testFrontendMessages() throws {
    do {
      try withTemporaryDirectory { path in
        try withHijackedBufferedErrorStream(in: path) { errorBuffer in
          let main = path.appending(component: "main.swift")
          let output = path.appending(component: "main.o")
          try localFileSystem.writeFileContents(main) {
            $0 <<< "print(\"hello, world!\")"
          }
          let diags = DiagnosticsEngine()
          let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
          var driver = try Driver(args: ["swiftc", main.pathString,
                                         "-use-frontend-parseable-output",
                                         "-o", output.pathString] + sdkArgumentsForTesting,
                                  env: ProcessEnv.vars,
                                  diagnosticsEngine: diags,
                                  fileSystem: localFileSystem)
          let jobs = try driver.planBuild()
          XCTAssertEqual(jobs.removingAutolinkExtractJobs().map(\.kind), [.compile, .link])
          XCTAssertEqual(jobs[0].outputs.count, 1)
          let compileArgs = jobs[0].commandLine
          XCTAssertTrue(compileArgs.contains((.flag("-frontend-parseable-output"))))
          try driver.run(jobs: jobs)
          let invocationErrorOutput = try localFileSystem.readFileContents(errorBuffer).description
          XCTAssertTrue(invocationErrorOutput.contains(
          """
          {
            "kind": "began",
            "name": "compile",
          """))
          XCTAssertTrue(invocationErrorOutput.contains(
          """
          {
            "kind": "finished",
            "name": "compile",
          """))
        }
      }
    }

    do {
      try assertDriverDiagnostics(args: ["swiftc", "foo.swift", "-parseable-output",
                                         "-use-frontend-parseable-output"]) {
        $1.expect(.error(Driver.Error.conflictingOptions(.parseableOutput,
                                                         .useFrontendParseableOutput)))
      }
    }
  }
}

