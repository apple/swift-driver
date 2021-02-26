//===--------------- JobExecutorTests.swift - Swift Execution Tests -------===//
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
import TSCBasic
import TSCUtility

@_spi(Testing) import SwiftDriver
import SwiftDriverExecution

extension Job.ArgTemplate: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) {
    self = .flag(value)
  }
}

class JobCollectingDelegate: JobExecutionDelegate {
  struct StubProcess: ProcessProtocol {
    static func launchProcess(arguments: [String], env: [String : String]) throws -> StubProcess {
      return .init()
    }

    var processID: TSCBasic.Process.ProcessID { .init(-1) }

    func waitUntilExit() throws -> ProcessResult {
      return ProcessResult(
        arguments: [],
        environment: [:],
        exitStatus: .terminated(code: EXIT_SUCCESS),
        output: Result.success(ByteString("test").contents),
        stderrOutput: Result.success([])
      )
    }
  }

  var started: [Job] = []
  var finished: [(Job, ProcessResult)] = []

  func jobFinished(job: Job, result: ProcessResult, pid: Int) {
    finished.append((job, result))
  }

  func jobStarted(job: Job, arguments: [String], pid: Int) {
    started.append(job)
  }

  func jobSkipped(job: Job) {}
}

extension DarwinToolchain {
  /// macOS SDK path, for testing only.
  var sdk: Result<AbsolutePath, Swift.Error> {
    Result {
      let result = try executor.checkNonZeroExit(
        args: "xcrun", "-sdk", "macosx", "--show-sdk-path",
        environment: env
      ).spm_chomp()
      return AbsolutePath(result)
    }
  }

  /// macOS resource directory, for testing only.
  var resourcesDirectory: Result<AbsolutePath, Swift.Error> {
    return Result {
      try getToolPath(.swiftCompiler).appending(RelativePath("../../lib/swift/macosx"))
    }
  }

  var clangRT: Result<AbsolutePath, Error> {
    resourcesDirectory.map { $0.appending(RelativePath("../clang/lib/darwin/libclang_rt.osx.a")) }
  }

  var compatibility50: Result<AbsolutePath, Error> {
    resourcesDirectory.map { $0.appending(component: "libswiftCompatibility50.a") }
  }

  var compatibilityDynamicReplacements: Result<AbsolutePath, Error> {
    resourcesDirectory.map { $0.appending(component: "libswiftCompatibilityDynamicReplacements.a") }
  }
}

final class JobExecutorTests: XCTestCase {
  func testDarwinBasic() throws {
#if os(macOS)
    let executor = try SwiftDriverExecutor(diagnosticsEngine: DiagnosticsEngine(),
                                           processSet: ProcessSet(),
                                           fileSystem: localFileSystem,
                                           env: ProcessEnv.vars)
    let toolchain = DarwinToolchain(env: ProcessEnv.vars, executor: executor)
    try withTemporaryDirectory { path in
      let foo = path.appending(component: "foo.swift")
      let main = path.appending(component: "main.swift")

      try localFileSystem.writeFileContents(foo) {
        $0 <<< "let foo = 5"
      }
      try localFileSystem.writeFileContents(main) {
        $0 <<< "print(foo)"
      }

      let exec = path.appending(component: "main")

      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      resolver.pathMapping = [
        .relative(RelativePath("foo.swift")): foo.pathString,
        .relative(RelativePath("main.swift")): main.pathString,
        .relative(RelativePath("main")): exec.pathString,
      ]

      let inputs: [String: TypedVirtualPath] = [
        "foo" : .init(file: .relative(RelativePath( "foo.swift")), type: .swift),
        "main": .init(file: .relative(RelativePath("main.swift")), type: .swift)
      ]

      let compileFoo = Job(
        moduleName: "main",
        kind: .compile,
        tool: .absolute(try toolchain.getToolPath(.swiftCompiler)),
        commandLine: [
          "-frontend",
          "-c",
          "-primary-file",
          .path(inputs[ "foo"]!.file),
          .path(inputs["main"]!.file),
          "-target", "x86_64-apple-darwin18.7.0",
          "-enable-objc-interop",
          "-sdk",
          .path(.absolute(try toolchain.sdk.get())),
          "-module-name", "main",
          "-o", .path(.temporary(RelativePath("foo.o"))),
        ],
        inputs: Array(inputs.values),
        primaryInputs: [inputs["foo"]!],
        outputs: [.init(file: .temporary(RelativePath("foo.o")), type: .object)]
      )

      let compileMain = Job(
        moduleName: "main",
        kind: .compile,
        tool: .absolute(try toolchain.getToolPath(.swiftCompiler)),
        commandLine: [
          "-frontend",
          "-c",
          .path(.relative(RelativePath("foo.swift"))),
          "-primary-file",
          .path(inputs["main"]!.file),
          "-target", "x86_64-apple-darwin18.7.0",
          "-enable-objc-interop",
          "-sdk",
          .path(.absolute(try toolchain.sdk.get())),
          "-module-name", "main",
          "-o", .path(.temporary(RelativePath("main.o"))),
        ],
        inputs: Array(inputs.values),
        primaryInputs: [inputs["main"]!],
        outputs: [.init(file: .temporary(RelativePath("main.o")), type: .object)]
      )

      let link = Job(
        moduleName: "main",
        kind: .link,
        tool: .absolute(try toolchain.getToolPath(.dynamicLinker)),
        commandLine: [
          .path(.temporary(RelativePath("foo.o"))),
          .path(.temporary(RelativePath("main.o"))),
          .path(.absolute(try toolchain.clangRT.get())),
          "-syslibroot", .path(.absolute(try toolchain.sdk.get())),
          "-lobjc", "-lSystem", "-arch", "x86_64",
          "-force_load", .path(.absolute(try toolchain.compatibility50.get())),
          "-force_load", .path(.absolute(try toolchain.compatibilityDynamicReplacements.get())),
          "-L", .path(.absolute(try toolchain.resourcesDirectory.get())),
          "-L", .path(.absolute(try toolchain.sdkStdlib(sdk: toolchain.sdk.get()))),
          "-rpath", "/usr/lib/swift", "-macosx_version_min", "10.14.0", "-no_objc_category_merging", "-o",
          .path(.relative(RelativePath("main"))),
        ],
        inputs: [
          .init(file: .temporary(RelativePath("foo.o")), type: .object),
          .init(file: .temporary(RelativePath("main.o")), type: .object),
        ],
        primaryInputs: [],
        outputs: [.init(file: .relative(RelativePath("main")), type: .image)]
      )

      let delegate = JobCollectingDelegate()
      let executor = MultiJobExecutor(workload: .all([compileFoo, compileMain, link]),
                                      resolver: resolver, executorDelegate: delegate, diagnosticsEngine: DiagnosticsEngine())
      try executor.execute(env: toolchain.env, fileSystem: localFileSystem)

      let output = try TSCBasic.Process.checkNonZeroExit(args: exec.pathString)
      XCTAssertEqual(output, "5\n")
      XCTAssertEqual(delegate.started.count, 3)

      let fooObject = try resolver.resolve(.path(.temporary(RelativePath("foo.o"))))
      XCTAssertTrue(localFileSystem.exists(AbsolutePath(fooObject)), "expected foo.o to be present in the temporary directory")
      try resolver.removeTemporaryDirectory()
      XCTAssertFalse(localFileSystem.exists(AbsolutePath(fooObject)), "expected foo.o to be removed from the temporary directory")
    }
#endif
  }

  func testStubProcessProtocol() throws {
    // This test fails intermittently on Linux
    // rdar://70067844
    #if !os(macOS)
      throw XCTSkip()
    #endif
    let job = Job(
      moduleName: "main",
      kind: .compile,
      tool: .absolute(AbsolutePath("/usr/bin/swift")),
      commandLine: [.flag("something")],
      inputs: [],
      primaryInputs: [],
      outputs: [.init(file: .temporary(RelativePath("main")), type: .object)]
    )

    let delegate = JobCollectingDelegate()
    let executor = MultiJobExecutor(
      workload: .all([job]), resolver: try ArgsResolver(fileSystem: localFileSystem),
      executorDelegate: delegate,
      diagnosticsEngine: DiagnosticsEngine(),
      processType: JobCollectingDelegate.StubProcess.self
    )
    try executor.execute(env: ProcessEnv.vars, fileSystem: localFileSystem)

    XCTAssertEqual(try delegate.finished[0].1.utf8Output(), "test")
  }

  func testSwiftDriverExecOverride() throws {
    var env = ProcessEnv.vars
    let envVarName = "SWIFT_DRIVER_SWIFT_FRONTEND_EXEC"
    let dummyPath = "/some/garbage/path/fnord"
    let executor = try SwiftDriverExecutor(diagnosticsEngine: DiagnosticsEngine(),
                                           processSet: ProcessSet(),
                                           fileSystem: localFileSystem,
                                           env: env)

    // DarwinToolchain
    env.removeValue(forKey: envVarName)
    let normalSwiftPath = try DarwinToolchain(env: env, executor: executor).getToolPath(.swiftCompiler)
    // Match Toolchain temporary shim of a fallback to looking for "swift" before failing.
    XCTAssertTrue(normalSwiftPath.basenameWithoutExt == "swift-frontend" ||
                  normalSwiftPath.basenameWithoutExt == "swift")

    env[envVarName] = dummyPath
    let overriddenSwiftPath = try DarwinToolchain(env: env, executor: executor).getToolPath(.swiftCompiler)
    XCTAssertEqual(overriddenSwiftPath, AbsolutePath(dummyPath))

    // GenericUnixToolchain
    env.removeValue(forKey: envVarName)
    let unixSwiftPath = try GenericUnixToolchain(env: env, executor: executor).getToolPath(.swiftCompiler)
    XCTAssertTrue(unixSwiftPath.basenameWithoutExt == "swift-frontend" ||
                  unixSwiftPath.basenameWithoutExt == "swift")

    env[envVarName] = dummyPath
    let unixOverriddenSwiftPath = try GenericUnixToolchain(env: env, executor: executor).getToolPath(.swiftCompiler)
    XCTAssertEqual(unixOverriddenSwiftPath, AbsolutePath(dummyPath))
  }

  func testInputModifiedDuringSingleJobBuild() throws {
    try withTemporaryDirectory { path in
      let main = path.appending(component: "main.swift")
      try localFileSystem.writeFileContents(main) {
        $0 <<< "let foo = 1"
      }

      var driver = try Driver(args: ["swift", main.pathString])
      let jobs = try driver.planBuild()
      XCTAssertTrue(jobs.count == 1 && jobs[0].requiresInPlaceExecution)

      // Change the file
      try localFileSystem.writeFileContents(main) {
        $0 <<< "let foo = 1"
      }

    #if os(Windows) // Swift on Windows doesn't support scripting at the time
      throw XCTSkip()
    #else
      XCTAssertThrowsError(try driver.run(jobs: jobs)) {
        XCTAssertEqual($0 as? Job.InputError,
                       .inputUnexpectedlyModified(TypedVirtualPath(file: .absolute(main), type: .swift)))
      }
    #endif
    }
  }

  func testShellEscapingArgsInJobDescription() throws {
    let executor = try SwiftDriverExecutor(diagnosticsEngine: DiagnosticsEngine(),
                                           processSet: ProcessSet(),
                                           fileSystem: localFileSystem,
                                           env: [:])
    let job = Job(moduleName: "Module",
                  kind: .compile,
                  tool: .absolute(.init("/path/to/the tool")),
                  commandLine: [.path(.absolute(.init("/with space"))),
                                .path(.absolute(.init("/withoutspace")))],
                  inputs: [], primaryInputs: [], outputs: [])
    XCTAssertEqual(try executor.description(of: job, forceResponseFiles: false),
                   "'/path/to/the tool' '/with space' /withoutspace")
  }

  func testInputModifiedDuringMultiJobBuild() throws {
    try withTemporaryDirectory { path in
      let main = path.appending(component: "main.swift")
      try localFileSystem.writeFileContents(main) {
        $0 <<< "let foo = 1"
      }
      let other = path.appending(component: "other.swift")
      try localFileSystem.writeFileContents(other) {
        $0 <<< "let bar = 2"
      }
      try assertDriverDiagnostics(args: ["swiftc", main.pathString, other.pathString]) {driver, verifier in
        let jobs = try driver.planBuild()
        XCTAssertTrue(jobs.count > 1)

        // Change the file
        try localFileSystem.writeFileContents(other) {
          $0 <<< "let bar = 3"
        }

        // FIXME: It's unfortunate we diagnose this twice, once for each job which uses the input.
        verifier.expect(.error("input file '\(other.description)' was modified during the build"))
        verifier.expect(.error("input file '\(other.description)' was modified during the build"))
        XCTAssertThrowsError(try driver.run(jobs: jobs))
      }
    }
  }

  func testTemporaryFileWriting() throws {
    try withTemporaryDirectory { path in
      let resolver = try ArgsResolver(fileSystem: localFileSystem, temporaryDirectory: .absolute(path))
      let tmpPath = VirtualPath.temporaryWithKnownContents(.init("one.txt"), "hello, world!".data(using: .utf8)!)
      let resolvedOnce = try resolver.resolve(.path(tmpPath))
      let readContents = try localFileSystem.readFileContents(.init(validating: resolvedOnce))
      XCTAssertEqual(readContents, "hello, world!")
      let resolvedTwice = try resolver.resolve(.path(tmpPath))
      XCTAssertEqual(resolvedOnce, resolvedTwice)
      let readContents2 = try localFileSystem.readFileContents(.init(validating: resolvedTwice))
      XCTAssertEqual(readContents2, readContents)
    }
  }

  func testResolveSquashedArgs() throws {
    try withTemporaryDirectory { path in
      let resolver = try ArgsResolver(fileSystem: localFileSystem, temporaryDirectory: .absolute(path))
      let tmpPath = VirtualPath.temporaryWithKnownContents(.init("one.txt"), "hello, world!".data(using: .utf8)!)
      let tmpPath2 = VirtualPath.temporaryWithKnownContents(.init("two.txt"), "goodbye!".data(using: .utf8)!)
      let resolvedCommandLine = try resolver.resolve(
        .squashedArgumentList(option: "--opt=", args: [.path(tmpPath), .path(tmpPath2)]))
      XCTAssertEqual(resolvedCommandLine, "--opt=\(path.appending(component: "one.txt").pathString) \(path.appending(component: "two.txt").pathString)")
      XCTAssertEqual(resolvedCommandLine.spm_shellEscaped(), "'--opt=\(path.appending(component: "one.txt").pathString) \(path.appending(component: "two.txt").pathString)'")
    }
  }

  func testSaveTemps() throws {
    do {
      try withTemporaryDirectory { path in
        let main = path.appending(component: "main.swift")
        try localFileSystem.writeFileContents(main) {
          $0 <<< "print(\"hello, world!\")"
        }
        let diags = DiagnosticsEngine()
        let executor = try SwiftDriverExecutor(diagnosticsEngine: diags,
                                               processSet: ProcessSet(),
                                               fileSystem: localFileSystem,
                                               env: ProcessEnv.vars)
        let outputPath = path.appending(component: "finalOutput")
        var driver = try Driver(args: ["swiftc", main.pathString,
                                       "-driver-filelist-threshold", "0",
                                       "-o", outputPath.pathString],
                                env: ProcessEnv.vars,
                                diagnosticsEngine: diags,
                                fileSystem: localFileSystem,
                                executor: executor)
        let jobs = try driver.planBuild()
        XCTAssertEqual(jobs.removingAutolinkExtractJobs().map(\.kind), [.compile, .link])
        XCTAssertEqual(jobs[0].outputs.count, 1)
        let compileOutput = jobs[0].outputs[0].file
        guard case .temporary(.init("main.o")) = compileOutput else {
          XCTFail("unexpected output")
          return
        }
        try driver.run(jobs: jobs)
        XCTAssertTrue(localFileSystem.exists(outputPath))
        // -save-temps wasn't passed, so ensure the temporary file was removed.
        XCTAssertFalse(
          localFileSystem.exists(.init(try executor.resolver.resolve(.path(driver.allSourcesFileList!))))
        )
        XCTAssertFalse(localFileSystem.exists(.init(try executor.resolver.resolve(.path(compileOutput)))))
      }
    }

    do {
      try withTemporaryDirectory { path in
        let main = path.appending(component: "main.swift")
        try localFileSystem.writeFileContents(main) {
          $0 <<< "print(\"hello, world!\")"
        }
        let diags = DiagnosticsEngine()
        let executor = try SwiftDriverExecutor(diagnosticsEngine: diags,
                                               processSet: ProcessSet(),
                                               fileSystem: localFileSystem,
                                               env: ProcessEnv.vars)
        let outputPath = path.appending(component: "finalOutput")
        var driver = try Driver(args: ["swiftc", main.pathString,
                                       "-save-temps",
                                       "-driver-filelist-threshold", "0",
                                       "-o", outputPath.pathString],
                                env: ProcessEnv.vars,
                                diagnosticsEngine: diags,
                                fileSystem: localFileSystem,
                                executor: executor)
        let jobs = try driver.planBuild()
        XCTAssertEqual(jobs.removingAutolinkExtractJobs().map(\.kind), [.compile, .link])
        XCTAssertEqual(jobs[0].outputs.count, 1)
        let compileOutput = jobs[0].outputs[0].file
        guard case .temporary(.init("main.o")) = compileOutput else {
          XCTFail("unexpected output")
          return
        }
        try driver.run(jobs: jobs)
        XCTAssertTrue(localFileSystem.exists(outputPath))
        // -save-temps was passed, so ensure the temporary file was not removed.
        XCTAssertTrue(
          localFileSystem.exists(.init(try executor.resolver.resolve(.path(driver.allSourcesFileList!))))
        )
        XCTAssertTrue(localFileSystem.exists(.init(try executor.resolver.resolve(.path(compileOutput)))))
      }
    }

    do {
      try withTemporaryDirectory { path in
        let main = path.appending(component: "main.swift")
        try localFileSystem.writeFileContents(main) {
          $0 <<< "print(\"hello, world!\")"
        }
        let diags = DiagnosticsEngine()
        let executor = try SwiftDriverExecutor(diagnosticsEngine: diags,
                                               processSet: ProcessSet(),
                                               fileSystem: localFileSystem,
                                               env: ProcessEnv.vars)
        let outputPath = path.appending(component: "finalOutput")
        var driver = try Driver(args: ["swiftc", main.pathString,
                                       "-driver-filelist-threshold", "0",
                                       "-Xfrontend", "-debug-crash-immediately",
                                       "-o", outputPath.pathString],
                                env: ProcessEnv.vars,
                                diagnosticsEngine: diags,
                                fileSystem: localFileSystem,
                                executor: executor)
        let jobs = try driver.planBuild()
        XCTAssertEqual(jobs.removingAutolinkExtractJobs().map(\.kind), [.compile, .link])
        XCTAssertEqual(jobs[0].outputs.count, 1)
        let compileOutput = jobs[0].outputs[0].file
        guard case .temporary(.init("main.o")) = compileOutput else {
          XCTFail("unexpected output")
          return
        }
        try? driver.run(jobs: jobs)
        // A job crashed, so ensure any temporary files written so far are preserved.
        XCTAssertTrue(
          localFileSystem.exists(.init(try executor.resolver.resolve(.path(driver.allSourcesFileList!))))
        )
      }
    }

  }
}
