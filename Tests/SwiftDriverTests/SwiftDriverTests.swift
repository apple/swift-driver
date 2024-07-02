//===--------------- SwiftDriverTests.swift - Swift Driver Tests -======---===//
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
@testable @_spi(Testing) import SwiftDriver
import SwiftDriverExecution
import SwiftOptions
import TSCBasic
import XCTest
import TestUtilities

private func executableName(_ name: String) -> String {
#if os(Windows)
  if name.count > 4, name.suffix(from: name.index(name.endIndex, offsetBy: -4)) == ".exe" {
    return name
  }
  return "\(name).exe"
#else
  return name
#endif
}

private func rebase(_ arc: String, at base: AbsolutePath = localFileSystem.currentWorkingDirectory!) -> String {
  base.appending(component: arc).nativePathString(escaped: false)
}

private func rebase(_ arcs: String..., at base: AbsolutePath = localFileSystem.currentWorkingDirectory!) -> String {
  base.appending(components: arcs).nativePathString(escaped: false)
}

private var testInputsPath: AbsolutePath {
  get throws {
    var root: AbsolutePath = try AbsolutePath(validating: #file)
    while root.basename != "Tests" {
      root = root.parentDirectory
    }
    return root.parentDirectory.appending(component: "TestInputs")
  }
}

func toPath(_ path: String, base: AbsolutePath = localFileSystem.currentWorkingDirectory!) throws -> VirtualPath {
  return try VirtualPath(path: path).resolvedRelativePath(base: base)
}

func toPathOption(_ path: String, base:  AbsolutePath = localFileSystem.currentWorkingDirectory!) throws -> Job.ArgTemplate {
  return .path(try toPath(path, base: base))
}

final class SwiftDriverTests: XCTestCase {
  private var ld: AbsolutePath!

  override func setUp() {
    do {
      self.ld = try withTemporaryDirectory(removeTreeOnDeinit: false) {
        let ld = $0.appending(component: executableName("ld64.lld"))
        try localFileSystem.writeFileContents(ld, bytes: "")
        try localFileSystem.chmod(.executable, path: AbsolutePath(validating: ld.nativePathString(escaped: false)))
        return ld
      }
    } catch {
      fatalError("unable to create stub 'ld' tool")
    }
  }

  override func tearDown() {
    try? localFileSystem.removeFileTree(AbsolutePath(validating: self.ld.dirname))
  }

  private var envWithFakeSwiftHelp: [String: String] {
    // During build-script builds, build products are not installed into the toolchain
    // until a project's tests pass. However, we're in the middle of those tests,
    // so there is no swift-help in the toolchain yet. Set the environment variable
    // as if we had found it for the purposes of testing build planning.
    var env = ProcessEnv.vars
    env["SWIFT_DRIVER_SWIFT_HELP_EXEC"] = "/tmp/.test-swift-help"
    return env
  }

  /// Determine if the test's execution environment has LLDB
  /// Used to skip tests that rely on LLDB in such environments.
  private func testEnvHasLLDB() throws -> Bool {
    let executor = try SwiftDriverExecutor(diagnosticsEngine: DiagnosticsEngine(),
                                           processSet: ProcessSet(),
                                           fileSystem: localFileSystem,
                                           env: ProcessEnv.vars)
    let toolchain: Toolchain
    #if os(macOS)
    toolchain = DarwinToolchain(env: ProcessEnv.vars, executor: executor)
    #elseif os(Windows)
    toolchain = WindowsToolchain(env: ProcessEnv.vars, executor: executor)
    #else
    toolchain = GenericUnixToolchain(env: ProcessEnv.vars, executor: executor)
    #endif
    do {
      _ = try toolchain.getToolPath(.lldb)
    } catch ToolchainError.unableToFind {
      return false
    }
    return true
  }

  func testInvocationRunModes() throws {

    let driver1 = try Driver.invocationRunMode(forArgs: ["swift"])
    XCTAssertEqual(driver1.mode, .normal(isRepl: false))
    XCTAssertEqual(driver1.args, ["swift"])

    let driver2 = try Driver.invocationRunMode(forArgs: ["swift", "-buzz"])
    XCTAssertEqual(driver2.mode, .normal(isRepl: false))
    XCTAssertEqual(driver2.args, ["swift", "-buzz"])

    let driver3 = try Driver.invocationRunMode(forArgs: ["swift", "/"])
    XCTAssertEqual(driver3.mode, .normal(isRepl: false))
    XCTAssertEqual(driver3.args, ["swift", "/"])

    let driver4 = try Driver.invocationRunMode(forArgs: ["swift", "./foo"])
    XCTAssertEqual(driver4.mode, .normal(isRepl: false))
    XCTAssertEqual(driver4.args, ["swift", "./foo"])

    let driver5 = try Driver.invocationRunMode(forArgs: ["swift", "repl"])
    XCTAssertEqual(driver5.mode, .normal(isRepl: true))
    XCTAssertEqual(driver5.args, ["swift", "-repl"])

    let driver6 = try Driver.invocationRunMode(forArgs: ["swift", "foo", "bar"])
    XCTAssertEqual(driver6.mode, .subcommand(executableName("swift-foo")))
    XCTAssertEqual(driver6.args, [executableName("swift-foo"), "bar"])

    let driver7 = try Driver.invocationRunMode(forArgs: ["swift", "-frontend", "foo", "bar"])
    XCTAssertEqual(driver7.mode, .subcommand(executableName("swift-frontend")))
    XCTAssertEqual(driver7.args, [executableName("swift-frontend"), "foo", "bar"])

    let driver8 = try Driver.invocationRunMode(forArgs: ["swift", "-modulewrap", "foo", "bar"])
    XCTAssertEqual(driver8.mode, .subcommand(executableName("swift-frontend")))
    XCTAssertEqual(driver8.args, [executableName("swift-frontend"), "-modulewrap", "foo", "bar"])
  }

  func testSubcommandsHandling() throws {

    XCTAssertNoThrow(try Driver(args: ["swift"]))
    XCTAssertNoThrow(try Driver(args: ["swift", "-I=foo"]))
    XCTAssertNoThrow(try Driver(args: ["swift", ".foo"]))
    XCTAssertNoThrow(try Driver(args: ["swift", "/foo"]))

    XCTAssertThrowsError(try Driver(args: ["swift", "foo"]))
  }

  func testDriverKindParsing() throws {
    func assertArgs(
      _ args: String...,
      parseTo driverKind: DriverKind,
      leaving remainingArgs: [String],
      file: StaticString = #file, line: UInt = #line
    ) throws {
      var args = args
      let result = try Driver.determineDriverKind(args: &args)

      XCTAssertEqual(result, driverKind, file: file, line: line)
      XCTAssertEqual(args, remainingArgs, file: file, line: line)
    }
    func assertArgsThrow(
      _ args: String...,
      file: StaticString = #file, line: UInt = #line
    ) throws {
      var args = args
      XCTAssertThrowsError(try Driver.determineDriverKind(args: &args))
    }

    try assertArgs("swift", parseTo: .interactive, leaving: [])
    try assertArgs("/path/to/swift", parseTo: .interactive, leaving: [])
    try assertArgs("swiftc", parseTo: .batch, leaving: [])
    try assertArgs(".build/debug/swiftc", parseTo: .batch, leaving: [])
    try assertArgs("swiftc", "--driver-mode=swift", parseTo: .interactive, leaving: [])
    try assertArgs("swift", "-zelda", parseTo: .interactive, leaving: ["-zelda"])
    try assertArgs("swiftc", "--driver-mode=swift", "swiftc",
                   parseTo: .interactive, leaving: ["swiftc"])
    try assertArgsThrow("driver")
    try assertArgsThrow("swiftc", "--driver-mode=blah")
    try assertArgsThrow("swiftc", "--driver-mode=")
  }

  func testCompilerMode() throws {
    do {
      let driver1 = try Driver(args: ["swift", "main.swift"])
      XCTAssertEqual(driver1.compilerMode, .immediate)

      let driver2 = try Driver(args: ["swift"])
      XCTAssertEqual(driver2.compilerMode, .intro)
    }

    do {
      let driver1 = try Driver(args: ["swiftc", "main.swift", "-whole-module-optimization"])
      XCTAssertEqual(driver1.compilerMode, .singleCompile)

      let driver2 = try Driver(args: ["swiftc", "main.swift", "-whole-module-optimization", "-no-whole-module-optimization"])
      XCTAssertEqual(driver2.compilerMode, .standardCompile)

      let driver3 = try Driver(args: ["swiftc", "main.swift", "-g"])
      XCTAssertEqual(driver3.compilerMode, .standardCompile)
    }
  }

  func testJoinedPathOptions() throws {
    var driver = try Driver(args: ["swiftc", "-c", "-I=/some/dir", "-F=other/relative/dir", "foo.swift"])
    let jobs = try driver.planBuild()
    XCTAssertTrue(jobs[0].commandLine.contains(.joinedOptionAndPath("-I=", .absolute(try .init(validating: "/some/dir")))))
    XCTAssertTrue(jobs[0].commandLine.contains(.joinedOptionAndPath("-F=", try toPath("other/relative/dir"))))
  }

  func testRelativeOptionOrdering() throws {
    var driver = try Driver(args: ["swiftc", "foo.swift",
                                   "-F", "/path/to/frameworks",
                                   "-Fsystem", "/path/to/systemframeworks",
                                   "-F", "/path/to/more/frameworks"])
    let jobs = try driver.planBuild()
    XCTAssertEqual(jobs[0].kind, .compile)
    // The relative ordering of -F and -Fsystem options should be preserved.
    XCTAssertTrue(jobs[0].commandLine.contains(subsequence: [.flag("-F"), .path(.absolute(try .init(validating: "/path/to/frameworks"))),
                                                             .flag("-Fsystem"), .path(.absolute(try .init(validating: "/path/to/systemframeworks"))),
                                                             .flag("-F"), .path(.absolute(try .init(validating: "/path/to/more/frameworks")))]))
  }

  func testBatchModeDiagnostics() throws {
      try assertNoDriverDiagnostics(args: "swiftc", "-enable-batch-mode") { driver in
        switch driver.compilerMode {
        case .batchCompile:
          break
        default:
          XCTFail("Expected batch compile, got \(driver.compilerMode)")
        }
      }

      try assertDriverDiagnostics(args: "swiftc", "-enable-batch-mode", "-whole-module-optimization") { driver, diagnostics in
        XCTAssertEqual(driver.compilerMode, .singleCompile)
        diagnostics.expect(.warning("ignoring '-enable-batch-mode' because '-whole-module-optimization' was also specified"))
      }

      try assertDriverDiagnostics(args: "swiftc", "-enable-batch-mode", "-whole-module-optimization", "-no-whole-module-optimization", "-index-file", "-module-name", "foo") { driver, diagnostics in
        XCTAssertEqual(driver.compilerMode, .singleCompile)
        diagnostics.expect(.warning("ignoring '-enable-batch-mode' because '-index-file' was also specified"))
      }

      try assertNoDriverDiagnostics(args: "swiftc", "-enable-batch-mode", "-whole-module-optimization", "-no-whole-module-optimization") { driver in
        switch driver.compilerMode {
        case .batchCompile:
          break
        default:
          XCTFail("Expected batch compile, got \(driver.compilerMode)")
        }
      }
  }

  func testHelp() throws {
    do {
      var driver = try Driver(args: ["swift", "--help"], env: envWithFakeSwiftHelp)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      let helpJob = plannedJobs.first!
      XCTAssertTrue(helpJob.kind == .help)
      XCTAssertTrue(helpJob.requiresInPlaceExecution)
      XCTAssertTrue(helpJob.tool.name.hasSuffix("swift-help"))
      let expected: [Job.ArgTemplate] = [.flag("swift")]
      XCTAssertEqual(helpJob.commandLine, expected)
    }

    do {
      var driver = try Driver(args: ["swiftc", "-help-hidden"], env: envWithFakeSwiftHelp)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      let helpJob = plannedJobs.first!
      XCTAssertTrue(helpJob.kind == .help)
      XCTAssertTrue(helpJob.requiresInPlaceExecution)
      XCTAssertTrue(helpJob.tool.name.hasSuffix("swift-help"))
      let expected: [Job.ArgTemplate] = [.flag("swiftc"), .flag("-show-hidden")]
      XCTAssertEqual(helpJob.commandLine, expected)
    }
  }

  func testRuntimeCompatibilityVersion() throws {
    try assertNoDriverDiagnostics(args: "swiftc", "a.swift", "-runtime-compatibility-version", "none")
  }

  func testInputFiles() throws {
    let driver1 = try Driver(args: ["swiftc", "a.swift", "/tmp/b.swift"])
    XCTAssertEqual(driver1.inputFiles,
                   [ TypedVirtualPath(file: try toPath("a.swift").intern(), type: .swift),
                     TypedVirtualPath(file: VirtualPath.absolute(try AbsolutePath(validating: "/tmp/b.swift")).intern(), type: .swift) ])

    let workingDirectory = localFileSystem.currentWorkingDirectory!.appending(components: "wobble")
    let tempDirectory = localFileSystem.currentWorkingDirectory!.appending(components: "tmp")

    let driver2 = try Driver(args: ["swiftc", "a.swift", "-working-directory", workingDirectory.pathString, rebase("b.swift", at: tempDirectory)])
    XCTAssertEqual(driver2.inputFiles,
                   [ TypedVirtualPath(file: VirtualPath.absolute(try AbsolutePath(validating: rebase("a.swift", at: workingDirectory))).intern(), type: .swift),
                     TypedVirtualPath(file: VirtualPath.absolute(try AbsolutePath(validating: rebase("b.swift", at: tempDirectory))).intern(), type: .swift) ])

    let driver3 = try Driver(args: ["swift", "-"])
    XCTAssertEqual(driver3.inputFiles, [ TypedVirtualPath(file: .standardInput, type: .swift )])

    let driver4 = try Driver(args: ["swift", "-", "-working-directory" , "-wobble"])
    XCTAssertEqual(driver4.inputFiles, [ TypedVirtualPath(file: .standardInput, type: .swift )])
  }

  func testDashE() throws {
    let fs = localFileSystem

    var driver1 = try Driver(args: ["swift", "-e", "print(1)", "-e", "print(2)", "foo/bar.swift", "baz/quux.swift"], fileSystem: fs)
    XCTAssertEqual(driver1.inputFiles.count, 1)
    XCTAssertEqual(driver1.inputFiles[0].file.basename, "main.swift")
    let tempFileContentsForDriver1 = try fs.readFileContents(XCTUnwrap(driver1.inputFiles[0].file.absolutePath))
    XCTAssertTrue(tempFileContentsForDriver1.description.hasSuffix("\nprint(1)\nprint(2)\n"))

    let plannedJobs = try driver1.planBuild().removingAutolinkExtractJobs()
    XCTAssertEqual(plannedJobs.count, 1)
    XCTAssertEqual(plannedJobs[0].kind, .interpret)
    XCTAssertEqual(plannedJobs[0].commandLine.drop(while: { $0 != .flag("--") }),
                   [.flag("--"), .flag("foo/bar.swift"), .flag("baz/quux.swift")])

    XCTAssertThrowsError(try Driver(args: ["swiftc", "baz/main.swift", "-e", "print(1)"], fileSystem: fs))
  }

  func testDashEJoined() throws {
    let fs = localFileSystem
    XCTAssertThrowsError(try Driver(args: ["swift", "-eprint(1)", "foo/bar.swift", "baz/quux.swift"], fileSystem: fs)) { error in
      XCTAssertEqual(error as? OptionParseError, .unknownOption(index: 0, argument: "-eprint(1)"))
    }
  }

  func testRecordedInputModificationDates() throws {
    guard let cwd = localFileSystem.currentWorkingDirectory else {
      fatalError()
    }

    try withTemporaryDirectory(dir: cwd, removeTreeOnDeinit: true) { path in
      let main = path.appending(component: "main.swift")
      let util = path.appending(component: "util.swift")
      let utilRelative = util.relative(to: cwd)
      try localFileSystem.writeFileContents(main, bytes: "print(hi)")
      try localFileSystem.writeFileContents(util, bytes: "let hi = \"hi\"")

      let mainMDate = try localFileSystem.lastModificationTime(for: .absolute(main))
      let utilMDate = try localFileSystem.lastModificationTime(for: .absolute(util))
      let driver = try Driver(args: [
        "swiftc", main.pathString, utilRelative.pathString,
      ])
      XCTAssertEqual(driver.recordedInputModificationDates, [
        .init(file: VirtualPath.absolute(main).intern(), type: .swift) : mainMDate,
        .init(file: VirtualPath.absolute(util).intern(), type: .swift) : utilMDate,
      ])
    }
  }

  func testPrimaryOutputKinds() throws {
    let driver1 = try Driver(args: ["swiftc", "foo.swift", "-emit-module"])
    XCTAssertEqual(driver1.compilerOutputType, .swiftModule)
    XCTAssertEqual(driver1.linkerOutputType, nil)

    let driver2 = try Driver(args: ["swiftc", "foo.swift", "-emit-library"])
    XCTAssertEqual(driver2.compilerOutputType, .object)
    XCTAssertEqual(driver2.linkerOutputType, .dynamicLibrary)

    let driver3 = try Driver(args: ["swiftc", "-static", "foo.swift", "-emit-library"])
    XCTAssertEqual(driver3.compilerOutputType, .object)
    XCTAssertEqual(driver3.linkerOutputType, .staticLibrary)

    let driver4 = try Driver(args: ["swiftc", "-lto=llvm-thin", "foo.swift", "-emit-library"])
    XCTAssertEqual(driver4.compilerOutputType, .llvmBitcode)
    let driver5 = try Driver(args: ["swiftc", "-lto=llvm-full", "foo.swift", "-emit-library"])
    XCTAssertEqual(driver5.compilerOutputType, .llvmBitcode)
  }

  func testLtoOutputModeClash() throws {
    let driver1 = try Driver(args: ["swiftc", "foo.swift", "-lto=llvm-full", "-static",
                                    "-emit-library", "-target", "x86_64-apple-macosx10.9"])
    XCTAssertEqual(driver1.compilerOutputType, .llvmBitcode)

    let driver2 = try Driver(args: ["swiftc", "foo.swift", "-lto=llvm-full",
                                    "-emit-library", "-target", "x86_64-apple-macosx10.9"])
    XCTAssertEqual(driver2.compilerOutputType, .llvmBitcode)

    let driver3 = try Driver(args: ["swiftc", "foo.swift", "-lto=llvm-full",
                                    "c", "-target", "x86_64-apple-macosx10.9"])
    XCTAssertEqual(driver3.compilerOutputType, .llvmBitcode)

    let driver4 = try Driver(args: ["swiftc", "foo.swift", "-c","-lto=llvm-full",
                                    "-target", "x86_64-apple-macosx10.9"])
    XCTAssertEqual(driver4.compilerOutputType, .llvmBitcode)

    let driver5 = try Driver(args: ["swiftc", "foo.swift", "-c","-lto=llvm-full",
                                    "-emit-bc", "-target", "x86_64-apple-macosx10.9"])
    XCTAssertEqual(driver5.compilerOutputType, .llvmBitcode)

    let driver6 = try Driver(args: ["swiftc", "foo.swift", "-emit-bc", "-c","-lto=llvm-full",
                                    "-target", "x86_64-apple-macosx10.9"])
    XCTAssertEqual(driver6.compilerOutputType, .llvmBitcode)
  }

  func testLtoOutputPath() throws {
    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "-lto=llvm-full", "-c", "-target", "x86_64-apple-macosx10.9"])
      XCTAssertEqual(driver.compilerOutputType, .llvmBitcode)
      XCTAssertEqual(driver.linkerOutputType, nil)
      let jobs = try driver.planBuild()
      XCTAssertEqual(jobs.count, 1)
      XCTAssertEqual(jobs[0].outputs.count, 1)
      XCTAssertEqual(jobs[0].outputs[0].file.basename, "foo.bc")
    }

    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "-lto=llvm-full", "-c", "-target", "x86_64-apple-macosx10.9", "-o", "foo.o"])
      XCTAssertEqual(driver.compilerOutputType, .llvmBitcode)
      XCTAssertEqual(driver.linkerOutputType, nil)
      let jobs = try driver.planBuild()
      XCTAssertEqual(jobs.count, 1)
      XCTAssertEqual(jobs[0].outputs.count, 1)
      XCTAssertEqual(jobs[0].outputs[0].file.basename, "foo.o")
    }
  }

  func testPrimaryOutputKindsDiagnostics() throws {
      try assertDriverDiagnostics(args: "swift", "-i") {
        $1.expect(.error("the flag '-i' is no longer required and has been removed; use 'swift input-filename'"))
      }
  }

  func testFilePrefixMapInvalidDiagnostic() throws {
    try assertDriverDiagnostics(args: "swiftc", "-c", "foo.swift", "-o", "foo.o", "-file-prefix-map", "invalid") {
      $1.expect(.error("values for '-file-prefix-map' must be in the format 'original=remapped', but 'invalid' was provided"))
    }
  }

  func testFilePrefixMapMultiplePassToFrontend() throws {
    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-file-prefix-map", "foo=bar", "-file-prefix-map", "dog=doggo") { driver in
        let jobs = try driver.planBuild()
        let commandLine = jobs[0].commandLine
        let index = commandLine.firstIndex(of: .flag("-file-prefix-map"))
        let lastIndex = commandLine.lastIndex(of: .flag("-file-prefix-map"))
        XCTAssertNotNil(index)
        XCTAssertNotNil(lastIndex)
        XCTAssertNotEqual(index, lastIndex)
        XCTAssertEqual(commandLine[index!.advanced(by: 1)], .flag("foo=bar"))
        XCTAssertEqual(commandLine[lastIndex!.advanced(by: 1)], .flag("dog=doggo"))
    }
  }

  func testIndexIncludeLocals() throws {
    // Make sure `-index-include-locals` is only passed to the frontend when
    // requested, not by default.
    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-index-store-path", "/tmp/idx") { driver in
        let jobs = try driver.planBuild()
        let commandLine = jobs[0].commandLine
        XCTAssertTrue(commandLine.contains(.flag("-index-store-path")))
        XCTAssertFalse(commandLine.contains(.flag("-index-include-locals")))
    }
    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-index-store-path", "/tmp/idx", "-index-include-locals") { driver in
        let jobs = try driver.planBuild()
        let commandLine = jobs[0].commandLine
        XCTAssertTrue(commandLine.contains(.flag("-index-store-path")))
        XCTAssertTrue(commandLine.contains(.flag("-index-include-locals")))
    }
  }

  func testMultiThreadingOutputs() throws {
    try assertDriverDiagnostics(args: "swiftc", "-c", "foo.swift", "bar.swift", "-o", "bar.ll", "-o", "foo.ll", "-num-threads", "2", "-whole-module-optimization") {
      $1.expect(.error("cannot specify -o when generating multiple output files"))
    }

    try assertDriverDiagnostics(args: "swiftc", "-c", "foo.swift", "bar.swift", "-o", "bar.ll", "-o", "foo.ll", "-num-threads", "0") {
      $1.expect(.error("cannot specify -o when generating multiple output files"))
    }
  }

  func testBaseOutputPaths() throws {
    // Test the combination of -c and -o includes the base output path.
    do {
      var driver = try Driver(args: ["swiftc", "-c", "foo.swift", "-o", "/some/output/path/bar.o"])
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(plannedJobs.count, 1)
      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertTrue(plannedJobs[0].commandLine.contains(.path(try VirtualPath(path: "/some/output/path/bar.o"))))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-emit-sil", "foo.swift", "-o", "/some/output/path/bar.sil"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertTrue(plannedJobs[0].commandLine.contains(.path(try VirtualPath(path: "/some/output/path/bar.sil"))))
    }

    do {
      // If no output is specified, verify we print to stdout for textual formats.
      var driver = try Driver(args: ["swiftc", "-emit-assembly", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertTrue(plannedJobs[0].commandLine.contains(.path(.standardOutput)))
    }
  }

    func testMultithreading() throws {
      XCTAssertNil(try Driver(args: ["swiftc"]).numParallelJobs)

      XCTAssertEqual(try Driver(args: ["swiftc", "-j", "4"]).numParallelJobs, 4)

      var env = ProcessEnv.vars
      env["SWIFTC_MAXIMUM_DETERMINISM"] = "1"
      XCTAssertEqual(try Driver(args: ["swiftc", "-j", "4"], env: env).numParallelJobs, 1)
    }

    func testMultithreadingDiagnostics() throws {
      try assertDriverDiagnostics(args: "swiftc", "-j", "0") {
        $1.expect(.error("invalid value '0' in '-j'"))
      }

      var env = ProcessEnv.vars
      env["SWIFTC_MAXIMUM_DETERMINISM"] = "1"
      try assertDriverDiagnostics(args: "swiftc", "-j", "8", env: env) {
        $1.expect(.remark("SWIFTC_MAXIMUM_DETERMINISM overriding -j"))
      }
    }

  func testDebugSettings() throws {
    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module") { driver in
      XCTAssertNil(driver.debugInfo.level)
      XCTAssertEqual(driver.debugInfo.format, .dwarf)
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module", "-g") { driver in
      XCTAssertEqual(driver.debugInfo.level, .astTypes)
      XCTAssertEqual(driver.debugInfo.format, .dwarf)
    }

    try assertNoDriverDiagnostics(args: "swiftc", "-g", "foo.swift", "-gline-tables-only") { driver in
      XCTAssertEqual(driver.debugInfo.level, .lineTables)
      XCTAssertEqual(driver.debugInfo.format, .dwarf)
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-debug-prefix-map", "foo=bar=baz", "-debug-prefix-map", "qux=") { driver in
        let jobs = try driver.planBuild()
        XCTAssertTrue(jobs[0].commandLine.contains(.flag("-debug-prefix-map")))
        XCTAssertTrue(jobs[0].commandLine.contains(.flag("foo=bar=baz")))
        XCTAssertTrue(jobs[0].commandLine.contains(.flag("-debug-prefix-map")))
        XCTAssertTrue(jobs[0].commandLine.contains(.flag("qux=")))
    }

    do {
      var env = ProcessEnv.vars
      env["SWIFT_DRIVER_TESTS_ENABLE_EXEC_PATH_FALLBACK"] = "1"
      env["RC_DEBUG_PREFIX_MAP"] = "old=new"
      var driver = try Driver(args: ["swiftc", "-c", "-target", "arm64-apple-macos12", "foo.swift"], env: env)
      let jobs = try driver.planBuild()
      XCTAssertTrue(jobs[0].commandLine.contains(.flag("-debug-prefix-map")))
      XCTAssertTrue(jobs[0].commandLine.contains(.flag("old=new")))
    }

    try assertDriverDiagnostics(args: "swiftc", "foo.swift", "-debug-prefix-map", "foo", "-debug-prefix-map", "bar") {
        $1.expect(.error("values for '-debug-prefix-map' must be in the format 'original=remapped', but 'foo' was provided"))
        $1.expect(.error("values for '-debug-prefix-map' must be in the format 'original=remapped', but 'bar' was provided"))
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module", "-g", "-debug-info-format=codeview") { driver in
      XCTAssertEqual(driver.debugInfo.level, .astTypes)
      XCTAssertEqual(driver.debugInfo.format, .codeView)

      let jobs = try driver.planBuild()
      XCTAssertTrue(jobs[0].commandLine.contains(.flag("-debug-info-format=codeview")))
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module", "-g", "-debug-info-format=dwarf") { driver in
      XCTAssertEqual(driver.debugInfo.format, .dwarf)

      let jobs = try driver.planBuild()
      XCTAssertTrue(jobs[0].commandLine.contains(.flag("-debug-info-format=dwarf")))
    }

    try assertDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module", "-debug-info-format=dwarf") {
      $1.expect(.error("option '-debug-info-format=' is missing a required argument (-g)"))
    }

    try assertDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module", "-g", "-debug-info-format=notdwarf") {
      $1.expect(.error("invalid value 'notdwarf' in '-debug-info-format='"))
    }

    try assertDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module", "-gdwarf-types", "-debug-info-format=codeview") {
      $1.expect(.error("argument '-debug-info-format=codeview' is not allowed with '-gdwarf-types'"))
    }

    try assertDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module", "-dwarf-version=0") {
      $1.expect(.error("invalid value '0' in '-dwarf-version="))
    }

    try assertDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module", "-dwarf-version=6") {
      $1.expect(.error("invalid value '6' in '-dwarf-version="))
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-g", "-c", "-file-compilation-dir", ".") { driver in
      let jobs = try driver.planBuild()
      let path = try VirtualPath.intern(path: ".")
      XCTAssertTrue(jobs[0].commandLine.contains(.flag("-file-compilation-dir")))
      XCTAssertTrue(jobs[0].commandLine.contains(.path(VirtualPath.lookup(path))))
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-g", "-c", "-working-directory", "/tmp") { driver in
      let jobs = try driver.planBuild()
      let path = try VirtualPath.intern(path: "/tmp")
      XCTAssertTrue(jobs[0].commandLine.contains(.flag("-file-compilation-dir")))
      XCTAssertTrue(jobs[0].commandLine.contains(.path(VirtualPath.lookup(path))))
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-g", "-c") { driver in
      let jobs = try driver.planBuild()
      XCTAssertTrue(jobs[0].commandLine.contains(.flag("-file-compilation-dir")))
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-c", "-file-compilation-dir", ".") { driver in
      let jobs = try driver.planBuild()
      XCTAssertFalse(jobs[0].commandLine.contains(.flag("-file-compilation-dir")))
    }
  }

  func testDwarfVersionSetting() throws {
    let driver = try Driver(args: ["swiftc", "foo.swift"])
    guard driver.isFrontendArgSupported(.dwarfVersion) else {
      throw XCTSkip("Skipping: compiler does not support '-dwarf-version'")
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module", "-g", "-debug-info-format=dwarf", "-dwarf-version=4") { driver in
        let jobs = try driver.planBuild()
        XCTAssertTrue(jobs[0].commandLine.contains(.flag("-dwarf-version=4")))
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-g", "-c", "-target", "x86_64-apple-macosx10.10") { driver in
      let jobs = try driver.planBuild()
      XCTAssertTrue(jobs[0].commandLine.contains(.flag("-dwarf-version=2")))
    }
    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-g", "-c", "-target", "x86_64-apple-macosx10.11") { driver in
      let jobs = try driver.planBuild()
      XCTAssertTrue(jobs[0].commandLine.contains(.flag("-dwarf-version=4")))
    }
    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-g", "-c", "-target", "x86_64-apple-macos14.0") { driver in
      let jobs = try driver.planBuild()
      XCTAssertTrue(jobs[0].commandLine.contains(.flag("-dwarf-version=4")))
    }
    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-g", "-c", "-target", "arm64-apple-ios8.0") { driver in
      let jobs = try driver.planBuild()
      XCTAssertTrue(jobs[0].commandLine.contains(.flag("-dwarf-version=2")))
    }
    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-g", "-c", "-target", "arm64-apple-ios9.0") { driver in
      let jobs = try driver.planBuild()
      XCTAssertTrue(jobs[0].commandLine.contains(.flag("-dwarf-version=4")))
    }
    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-g", "-c", "-target", "x86_64-apple-ios17-macabi") { driver in
      let jobs = try driver.planBuild()
      XCTAssertTrue(jobs[0].commandLine.contains(.flag("-dwarf-version=4")))
    }
    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-g", "-c", "-target", "arm64-apple-tvos17.0") { driver in
      let jobs = try driver.planBuild()
      XCTAssertTrue(jobs[0].commandLine.contains(.flag("-dwarf-version=4")))
    }
    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-g", "-c", "-target", "arm64_32-apple-watchos10.0") { driver in
      let jobs = try driver.planBuild()
      XCTAssertTrue(jobs[0].commandLine.contains(.flag("-dwarf-version=4")))
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-g", "-c", "-target", "x86_64-apple-macosx15") { driver in
      let jobs = try driver.planBuild()
      XCTAssertTrue(jobs[0].commandLine.contains(.flag("-dwarf-version=5")))
    }
    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-g", "-c", "-target", "arm64-apple-ios18.0") { driver in
      let jobs = try driver.planBuild()
      XCTAssertTrue(jobs[0].commandLine.contains(.flag("-dwarf-version=5")))
    }
    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-g", "-c", "-target", "arm64_32-apple-watchos11") { driver in
      let jobs = try driver.planBuild()
      XCTAssertTrue(jobs[0].commandLine.contains(.flag("-dwarf-version=5")))
    }
    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-g", "-c", "-target", "arm64-apple-tvos18") { driver in
      let jobs = try driver.planBuild()
      XCTAssertTrue(jobs[0].commandLine.contains(.flag("-dwarf-version=5")))
    }
    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-g", "-c", "-target", "arm64-apple-xros1.0-simulator") { driver in
      let jobs = try driver.planBuild()
      XCTAssertTrue(jobs[0].commandLine.contains(.flag("-dwarf-version=4")))
    }
    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-g", "-c", "-target", "arm64-apple-xros2.0") { driver in
      let jobs = try driver.planBuild()
      XCTAssertTrue(jobs[0].commandLine.contains(.flag("-dwarf-version=5")))
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-c", "-file-compilation-dir", ".") { driver in
      let jobs = try driver.planBuild()
      XCTAssertFalse(jobs[0].commandLine.contains(.flag("-file-compilation-dir")))
    }
  }

  func testCoverageSettings() throws {
    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-coverage-prefix-map", "foo=bar=baz", "-coverage-prefix-map", "qux=") { driver in
      let jobs = try driver.planBuild()
      XCTAssertTrue(jobs[0].commandLine.contains(.flag("-coverage-prefix-map")))
      XCTAssertTrue(jobs[0].commandLine.contains(.flag("foo=bar=baz")))
      XCTAssertTrue(jobs[0].commandLine.contains(.flag("-coverage-prefix-map")))
      XCTAssertTrue(jobs[0].commandLine.contains(.flag("qux=")))
    }

    try assertDriverDiagnostics(args: "swiftc", "foo.swift", "-coverage-prefix-map", "foo", "-coverage-prefix-map", "bar") {
      $1.expect(.error("values for '-coverage-prefix-map' must be in the format 'original=remapped', but 'foo' was provided"))
      $1.expect(.error("values for '-coverage-prefix-map' must be in the format 'original=remapped', but 'bar' was provided"))
    }
  }

  func testHermeticSealAtLink() throws {
    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-experimental-hermetic-seal-at-link", "-lto=llvm-full") { driver in
      let jobs = try driver.planBuild()
      XCTAssertTrue(jobs[0].commandLine.contains(.flag("-enable-llvm-vfe")))
      XCTAssertTrue(jobs[0].commandLine.contains(.flag("-enable-llvm-wme")))
      XCTAssertTrue(jobs[0].commandLine.contains(.flag("-conditional-runtime-records")))
      XCTAssertTrue(jobs[0].commandLine.contains(.flag("-internalize-at-link")))
      XCTAssertTrue(jobs[0].commandLine.contains(.flag("-lto=llvm-full")))
    }

    try assertDriverDiagnostics(args: "swiftc", "foo.swift", "-experimental-hermetic-seal-at-link") {
      $1.expect(.error("-experimental-hermetic-seal-at-link requires -lto=llvm-full or -lto=llvm-thin"))
    }

    try assertDriverDiagnostics(args: "swiftc", "foo.swift", "-experimental-hermetic-seal-at-link", "-lto=llvm-full", "-enable-library-evolution") {
      $1.expect(.error("Cannot use -experimental-hermetic-seal-at-link with -enable-library-evolution"))
    }
  }

  func testABIDescriptorOnlyWhenEnableEvolution() throws {
    let flagName = "-empty-abi-descriptor"
    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift") { driver in
      let jobs = try driver.planBuild()
      let command = jobs[0].commandLine
      XCTAssertTrue(command.contains(.flag(flagName)))
    }
    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-enable-library-evolution") { driver in
      let jobs = try driver.planBuild()
      let command = jobs[0].commandLine
      XCTAssertFalse(command.contains(.flag(flagName)))
    }
  }

  func testModuleSettings() throws {
    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift") { driver in
      XCTAssertNil(driver.moduleOutputInfo.output)
      XCTAssertEqual(driver.moduleOutputInfo.name, "foo")
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-g") { driver in
      let pathHandle = driver.moduleOutputInfo.output?.outputPath
      XCTAssertTrue(matchTemporary(VirtualPath.lookup(pathHandle!), "foo.swiftmodule"))
      XCTAssertEqual(driver.moduleOutputInfo.name, "foo")
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-module-name", "wibble", "bar.swift", "-g") { driver in
      let pathHandle = driver.moduleOutputInfo.output?.outputPath
      XCTAssertTrue(matchTemporary(VirtualPath.lookup(pathHandle!), "wibble.swiftmodule"))
      XCTAssertEqual(driver.moduleOutputInfo.name, "wibble")
    }

    try assertNoDriverDiagnostics(args: "swiftc", "-emit-module", "foo.swift", "-module-name", "wibble", "bar.swift") { driver in
      XCTAssertEqual(driver.moduleOutputInfo.output, .topLevel(try toPath("wibble.swiftmodule").intern()))
      XCTAssertEqual(driver.moduleOutputInfo.name, "wibble")
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "bar.swift") { driver in
      XCTAssertNil(driver.moduleOutputInfo.output)
      XCTAssertEqual(driver.moduleOutputInfo.name, "main")
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "bar.swift", "-emit-library", "-o", "libWibble.so") { driver in
      XCTAssertEqual(driver.moduleOutputInfo.name, "Wibble")
    }

    try assertDriverDiagnostics(args: "swiftc", "foo.swift", "bar.swift", "-emit-library", "-o", "libWibble.so", "-module-name", "Swift") {
        $1.expect(.error("module name \"Swift\" is reserved for the standard library"))
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "bar.swift", "-emit-module", "-emit-library", "-o", "some/dir/libFoo.so", "-module-name", "MyModule") { driver in
      XCTAssertEqual(driver.moduleOutputInfo.output, .topLevel(try toPath("some/dir/MyModule.swiftmodule").intern()))
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "bar.swift", "-emit-module", "-emit-library", "-o", "/", "-module-name", "MyModule") { driver in
      XCTAssertEqual(driver.moduleOutputInfo.output, .topLevel(try VirtualPath.intern(path: "/MyModule.swiftmodule")))
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "bar.swift", "-emit-module", "-emit-library", "-o", "../../some/other/dir/libFoo.so", "-module-name", "MyModule") { driver in
      XCTAssertEqual(driver.moduleOutputInfo.output, .topLevel(try toPath("../../some/other/dir/MyModule.swiftmodule").intern()))
    }
  }

  func testModuleNameFallbacks() throws {
    try assertNoDriverDiagnostics(args: "swiftc", "file.foo.swift")
    try assertNoDriverDiagnostics(args: "swiftc", ".foo.swift")
    try assertNoDriverDiagnostics(args: "swiftc", "foo-bar.swift")
  }

  func testPackageNameFlag() throws {
    // -package-name com.perf.my-pkg (valid string)
    try assertNoDriverDiagnostics(args: "swiftc", "file.swift", "bar.swift", "-module-name", "MyModule", "-package-name", "com.perf.my-pkg", "-emit-module", "-emit-module-path", "../../path/to/MyModule.swiftmodule") { driver in
      XCTAssertEqual(driver.packageName, "com.perf.my-pkg")
      XCTAssertEqual(driver.moduleOutputInfo.output, .topLevel(try toPath("../../path/to/MyModule.swiftmodule").intern()))
    }

    // -package-name is not passed and file doesn't contain `package` decls; should pass
    try assertNoDriverDiagnostics(args: "swiftc", "file.swift") { driver in
      XCTAssertNil(driver.packageName)
      XCTAssertEqual(driver.moduleOutputInfo.name, "file")
    }

    // -package-name 123a!@#$ (valid string)
    try assertNoDriverDiagnostics(args: "swiftc", "file.swift", "-module-name", "Foo", "-package-name", "123a!@#$") { driver in
      XCTAssertEqual(driver.packageName, "123a!@#$")
    }

    // -package-name input is an empty string
    try assertDriverDiagnostics(args: "swiftc", "file.swift", "-package-name", "") {
      $1.expect(.error("package-name is empty"))
    }
  }

  func testStandardCompileJobs() throws {
    var driver1 = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-module-name", "Test"])
    let plannedJobs = try driver1.planBuild().removingAutolinkExtractJobs()
    XCTAssertEqual(plannedJobs.count, 3)
    XCTAssertEqual(plannedJobs[0].outputs.count, 1)
    XCTAssertTrue(matchTemporary(plannedJobs[0].outputs.first!.file, "foo.o"))
    XCTAssertEqual(plannedJobs[1].outputs.count, 1)
    XCTAssertTrue(matchTemporary(plannedJobs[1].outputs.first!.file, "bar.o"))
    XCTAssertTrue(plannedJobs[2].tool.name.contains(executableName("clang")))
    XCTAssertEqual(plannedJobs[2].outputs.count, 1)
    XCTAssertEqual(plannedJobs[2].outputs.first!.file, try toPath(executableName("Test")))

    // Forwarding of arguments.
    let workingDirectory = localFileSystem.currentWorkingDirectory!.appending(components: "tmp")

    var driver2 = try Driver(args: ["swiftc", "-color-diagnostics", "foo.swift", "bar.swift", "-working-directory", workingDirectory.pathString, "-api-diff-data-file", "diff.txt", "-Xfrontend", "-HI", "-no-color-diagnostics", "-g"])
    let plannedJobs2 = try driver2.planBuild()
    let compileJob = try plannedJobs2.findJob(.compile)
    XCTAssert(compileJob.commandLine.contains(Job.ArgTemplate.path(.absolute(try AbsolutePath(validating: rebase("diff.txt", at: workingDirectory))))))
    XCTAssert(compileJob.commandLine.contains(.flag("-HI")))
    XCTAssert(!compileJob.commandLine.contains(.flag("-Xfrontend")))
    XCTAssert(compileJob.commandLine.contains(.flag("-no-color-diagnostics")))
    XCTAssert(!compileJob.commandLine.contains(.flag("-color-diagnostics")))
    XCTAssert(compileJob.commandLine.contains(.flag("-target")))
    XCTAssert(compileJob.commandLine.contains(.flag(driver2.targetTriple.triple)))
    XCTAssert(compileJob.commandLine.contains(.flag("-enable-anonymous-context-mangled-names")))

    var driver3 = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-emit-library", "-module-name", "Test"])
    let plannedJobs3 = try driver3.planBuild()
    XCTAssertTrue(plannedJobs3[0].commandLine.contains(.flag("-module-name")))
    XCTAssertTrue(plannedJobs3[0].commandLine.contains(.flag("Test")))
    XCTAssertTrue(plannedJobs3[0].commandLine.contains(.flag("-parse-as-library")))
  }

  func testModuleNaming() throws {
    XCTAssertEqual(try Driver(args: ["swiftc", "foo.swift"]).moduleOutputInfo.name, "foo")
    XCTAssertEqual(try Driver(args: ["swiftc", "foo.swift", "-o", "a.out"]).moduleOutputInfo.name, "a")

    // This is silly, but necessary for compatibility with the integrated driver.
    XCTAssertEqual(try Driver(args: ["swiftc", "foo.swift", "-o", "a.out.optimized"]).moduleOutputInfo.name, "main")

    XCTAssertEqual(try Driver(args: ["swiftc", "foo.swift", "-o", "a.out.optimized", "-module-name", "bar"]).moduleOutputInfo.name, "bar")
    XCTAssertEqual(try Driver(args: ["swiftc", "foo.swift", "-o", "+++.out"]).moduleOutputInfo.name, "main")
    XCTAssertEqual(try Driver(args: ["swift"]).moduleOutputInfo.name, "REPL")
    XCTAssertEqual(try Driver(args: ["swiftc", "foo.swift", "-emit-library", "-o", "libBaz.dylib"]).moduleOutputInfo.name, "Baz")

    try assertDriverDiagnostics(
      args: ["swiftc", "foo.swift", "-module-name", "", "file.foo.swift"]
    ) {
      $1.expect(.error("module name \"\" is not a valid identifier"))
    }

    try assertDriverDiagnostics(
      args: ["swiftc", "foo.swift", "-module-name", "123", "file.foo.swift"]
    ) {
      $1.expect(.error("module name \"123\" is not a valid identifier"))
    }
  }

  func testEmitModuleSeparatelyDiagnosticPath() throws {
    try withTemporaryFile { fileMapFile in
      let outputMapContents: ByteString = """
      {
        "": {
          "diagnostics": "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/master.dia",
          "emit-module-diagnostics": "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/master.emit-module.dia"
        },
        "foo.swift": {
          "diagnostics": "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.dia"
        }
      }
      """
      try localFileSystem.writeFileContents(fileMapFile.path, bytes: outputMapContents)

      // Plain (batch/single-file) compile
      do {
        var driver = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-output-file-map", fileMapFile.path.pathString,
                                       "-emit-library", "-module-name", "Test", "-serialize-diagnostics"])
        let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
        XCTAssertEqual(plannedJobs.count, 3)
        XCTAssertTrue(plannedJobs[0].kind == .emitModule)
        XCTAssertTrue(plannedJobs[1].kind == .compile)
        XCTAssertTrue(plannedJobs[2].kind == .link)
        XCTAssertTrue(plannedJobs[0].commandLine.contains(subsequence: ["-serialize-diagnostics-path", .path(.absolute(try .init(validating: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/master.emit-module.dia")))]))
        XCTAssertTrue(plannedJobs[1].commandLine.contains(subsequence: ["-serialize-diagnostics-path", .path(.absolute(try .init(validating: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.dia")))]))
      }

      // WMO
      do {
        var driver = try Driver(args: ["swiftc", "foo.swift", "-whole-module-optimization", "-emit-module",
                                       "-output-file-map", fileMapFile.path.pathString, "-disable-cmo",
                                       "-emit-library", "-module-name", "Test", "-serialize-diagnostics"])
        let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
        XCTAssertEqual(plannedJobs.count, 3)
        XCTAssertTrue(plannedJobs[0].kind == .compile)
        XCTAssertTrue(plannedJobs[1].kind == .emitModule)
        XCTAssertTrue(plannedJobs[2].kind == .link)
        XCTAssertTrue(plannedJobs[0].commandLine.contains(subsequence: ["-serialize-diagnostics-path", .path(.absolute(try .init(validating: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/master.dia")))]))
        XCTAssertTrue(plannedJobs[1].commandLine.contains(subsequence: ["-serialize-diagnostics-path", .path(.absolute(try .init(validating: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/master.emit-module.dia")))]))
      }
    }
  }

  func testEmitModuleSeparatelyDependenciesPath() throws {
    try withTemporaryFile { fileMapFile in
      let outputMapContents: ByteString = """
      {
        "": {
          "dependencies": "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/master.d",
          "emit-module-dependencies": "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/master.emit-module.d"
        },
        "foo.swift": {
          "dependencies": "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.d"
        }
      }
      """
      try localFileSystem.writeFileContents(fileMapFile.path, bytes: outputMapContents)

      // Plain (batch/single-file) compile
      do {
        var driver = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-output-file-map", fileMapFile.path.pathString,
                                       "-emit-library", "-module-name", "Test", "-emit-dependencies"])
        let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
        XCTAssertEqual(plannedJobs.count, 3)
        XCTAssertTrue(plannedJobs[0].kind == .emitModule)
        XCTAssertTrue(plannedJobs[1].kind == .compile)
        XCTAssertTrue(plannedJobs[2].kind == .link)
        XCTAssertTrue(plannedJobs[0].commandLine.contains(subsequence: ["-emit-dependencies-path", .path(.absolute(try .init(validating: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/master.emit-module.d")))]))
        XCTAssertTrue(plannedJobs[1].commandLine.contains(subsequence: ["-emit-dependencies-path", .path(.absolute(try .init(validating: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.d")))]))
      }

      // WMO
      do {
        var driver = try Driver(args: ["swiftc", "foo.swift", "-whole-module-optimization", "-emit-module",
                                       "-output-file-map", fileMapFile.path.pathString, "-disable-cmo",
                                       "-emit-library", "-module-name", "Test", "-emit-dependencies"])
        let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
        XCTAssertEqual(plannedJobs.count, 3)
        XCTAssertTrue(plannedJobs[0].kind == .compile)
        XCTAssertTrue(plannedJobs[1].kind == .emitModule)
        XCTAssertTrue(plannedJobs[2].kind == .link)
        XCTAssertTrue(plannedJobs[0].commandLine.contains(subsequence: ["-emit-dependencies-path", .path(.absolute(try .init(validating: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/master.d")))]))
        XCTAssertTrue(plannedJobs[1].commandLine.contains(subsequence: ["-emit-dependencies-path", .path(.absolute(try .init(validating: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/master.emit-module.d")))]))
      }
    }
  }

  func testOutputFileMapLoading() throws {
    let objroot: AbsolutePath =
        try AbsolutePath(validating: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build")

    let contents = ByteString("""
    {
      "": {
        "swift-dependencies": "\(objroot.appending(components: "master.swiftdeps").nativePathString(escaped: true))"
      },
      "/tmp/foo/Sources/foo/foo.swift": {
        "dependencies": "\(objroot.appending(components: "foo.d").nativePathString(escaped: true))",
        "object": "\(objroot.appending(components: "foo.swift.o").nativePathString(escaped: true))",
        "swiftmodule": "\(objroot.appending(components: "foo~partial.swiftmodule").nativePathString(escaped: true))",
        "swift-dependencies": "\(objroot.appending(components: "foo.swiftdeps").nativePathString(escaped: true))"
      }
    }
    """.utf8)

    try withTemporaryFile { file in
      try assertNoDiagnostics { diags in
        try localFileSystem.writeFileContents(file.path, bytes: contents)
        let outputFileMap = try OutputFileMap.load(fileSystem: localFileSystem, file: .absolute(file.path), diagnosticEngine: diags)

        let object = try outputFileMap.getOutput(inputFile: VirtualPath.intern(path: "/tmp/foo/Sources/foo/foo.swift"), outputType: .object)
        XCTAssertEqual(VirtualPath.lookup(object).name, objroot.appending(components: "foo.swift.o").pathString)

        let masterDeps = try outputFileMap.getOutput(inputFile: VirtualPath.intern(path: ""), outputType: .swiftDeps)
        XCTAssertEqual(VirtualPath.lookup(masterDeps).name, objroot.appending(components: "master.swiftdeps").pathString)
      }
    }
  }

  func testFindingObjectPathFromllvmBCPath() throws {
    let objroot: AbsolutePath =
        try AbsolutePath(validating: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build")

    let contents = ByteString(
      """
      {
        "": {
          "swift-dependencies": "\(objroot.appending(components: "master.swiftdeps").nativePathString(escaped: true))"
        },
        "/tmp/foo/Sources/foo/foo.swift": {
          "dependencies": "\(objroot.appending(components: "foo.d").nativePathString(escaped: true))",
          "object": "\(objroot.appending(components: "foo.swift.o").nativePathString(escaped: true))",
          "swiftmodule": "\(objroot.appending(components: "foo~partial.swiftmodule").nativePathString(escaped: true))",
          "swift-dependencies": "\(objroot.appending(components: "foo.swiftdeps").nativePathString(escaped: true))",
          "llvm-bc": "\(objroot.appending(components: "foo.swift.bc").nativePathString(escaped: true))"
        }
      }
      """.utf8
    )
    try withTemporaryFile { file in
      try assertNoDiagnostics { diags in
        try localFileSystem.writeFileContents(file.path, bytes: contents)
        let outputFileMap = try OutputFileMap.load(fileSystem: localFileSystem, file: .absolute(file.path), diagnosticEngine: diags)

        let obj = try outputFileMap.getOutput(inputFile: VirtualPath.intern(path: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.swift.bc"), outputType: .object)
        XCTAssertEqual(VirtualPath.lookup(obj).name, objroot.appending(components: "foo.swift.o").pathString)
      }
    }
  }

  func testOutputFileMapLoadingDocAndSourceinfo() throws {
    let objroot: AbsolutePath =
        try AbsolutePath(validating: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build")

    let contents = ByteString(
      """
      {
        "": {
          "swift-dependencies": "\(objroot.appending(components: "master.swiftdeps").nativePathString(escaped: true))"
        },
        "/tmp/foo/Sources/foo/foo.swift": {
          "dependencies": "\(objroot.appending(components: "foo.d").nativePathString(escaped: true))",
          "object": "\(objroot.appending(components: "foo.swift.o").nativePathString(escaped: true))",
          "swiftmodule": "\(objroot.appending(components: "foo~partial.swiftmodule").nativePathString(escaped: true))",
          "swift-dependencies": "\(objroot.appending(components: "foo.swiftdeps").nativePathString(escaped: true))"
        }
      }
      """.utf8
    )

    try withTemporaryFile { file in
      try assertNoDiagnostics { diags in
        try localFileSystem.writeFileContents(file.path, bytes: contents)
        let outputFileMap = try OutputFileMap.load(fileSystem: localFileSystem, file: .absolute(file.path), diagnosticEngine: diags)

        let doc = try outputFileMap.getOutput(inputFile: VirtualPath.intern(path: "/tmp/foo/Sources/foo/foo.swift"), outputType: .swiftDocumentation)
        XCTAssertEqual(VirtualPath.lookup(doc).name, objroot.appending(components: "foo~partial.swiftdoc").pathString)

        let source = try outputFileMap.getOutput(inputFile: VirtualPath.intern(path: "/tmp/foo/Sources/foo/foo.swift"), outputType: .swiftSourceInfoFile)
        XCTAssertEqual(VirtualPath.lookup(source).name, objroot.appending(components: "foo~partial.swiftsourceinfo").pathString)
      }
    }
  }

  func testIndexUnitOutputPath() throws {
    let contents = ByteString(
      """
      {
        "/tmp/main.swift": {
          "object": "/tmp/build1/main.o",
          "index-unit-output-path": "/tmp/build2/main.o",
        },
        "/tmp/second.swift": {
          "object": "/tmp/build1/second.o",
          "index-unit-output-path": "/tmp/build2/second.o",
        }
      }
      """.utf8
    )

    func getFileListElements(for filelistOpt: String, job: Job) -> [VirtualPath] {
      let optIndex = job.commandLine.firstIndex(of: .flag(filelistOpt))!
      let value = job.commandLine[job.commandLine.index(after: optIndex)]
      guard case let .path(.fileList(_, valueFileList)) = value else {
        XCTFail("Argument wasn't a filelist")
        return []
      }
      guard case let .list(inputs) = valueFileList else {
        XCTFail("FileList wasn't List")
        return []
      }
      return inputs
    }

    try withTemporaryFile { file in
      try assertNoDiagnostics { diags in
        try localFileSystem.writeFileContents(file.path, bytes: contents)

        // 1. Incremental mode (single primary file)
        // a) without filelists
        var driver = try Driver(args: [
          "swiftc", "-c",
          "-output-file-map", file.path.pathString,
          "-module-name", "test", "/tmp/second.swift", "/tmp/main.swift"
        ])
        var jobs = try driver.planBuild()
        XCTAssertTrue(jobs[0].commandLine.contains(subsequence: ["-o", .path(.absolute(try .init(validating: "/tmp/build1/second.o")))]))
        XCTAssertTrue(jobs[1].commandLine.contains(subsequence: ["-o", .path(.absolute(try .init(validating: "/tmp/build1/main.o")))]))
        XCTAssertTrue(jobs[0].commandLine.contains(subsequence: ["-index-unit-output-path", .path(.absolute(try .init(validating: "/tmp/build2/second.o")))]))
        XCTAssertTrue(jobs[1].commandLine.contains(subsequence: ["-index-unit-output-path", .path(.absolute(try .init(validating: "/tmp/build2/main.o")))]))

        // b) with filelists
        driver = try Driver(args: [
          "swiftc", "-c", "-driver-filelist-threshold=0",
          "-output-file-map", file.path.pathString,
          "-module-name", "test", "/tmp/second.swift", "/tmp/main.swift"
        ])
        jobs = try driver.planBuild()
        XCTAssertEqual(getFileListElements(for: "-output-filelist", job: jobs[0]),
                       [.absolute(try .init(validating: "/tmp/build1/second.o"))])
        XCTAssertEqual(getFileListElements(for: "-index-unit-output-path-filelist", job: jobs[0]),
                       [.absolute(try .init(validating: "/tmp/build2/second.o"))])
        XCTAssertEqual(getFileListElements(for: "-output-filelist", job: jobs[1]),
                       [.absolute(try .init(validating: "/tmp/build1/main.o"))])
        XCTAssertEqual(getFileListElements(for: "-index-unit-output-path-filelist", job: jobs[1]),
                       [.absolute(try .init(validating: "/tmp/build2/main.o"))])

        // 2. Batch mode (two primary files)
        // a) without filelists
        driver = try Driver(args: [
          "swiftc", "-c", "-enable-batch-mode", "-driver-batch-count", "1",
          "-output-file-map", file.path.pathString,
          "-module-name", "test", "/tmp/second.swift", "/tmp/main.swift"
        ])
        jobs = try driver.planBuild()
        XCTAssertTrue(jobs[0].commandLine.contains(subsequence: ["-o", .path(.absolute(try .init(validating: "/tmp/build1/second.o")))]))
        XCTAssertTrue(jobs[0].commandLine.contains(subsequence: ["-o", .path(.absolute(try .init(validating: "/tmp/build1/main.o")))]))
        XCTAssertTrue(jobs[0].commandLine.contains(subsequence: ["-index-unit-output-path", .path(.absolute(try .init(validating: "/tmp/build2/second.o")))]))
        XCTAssertTrue(jobs[0].commandLine.contains(subsequence: ["-index-unit-output-path", .path(.absolute(try .init(validating: "/tmp/build2/main.o")))]))

        // b) with filelists
        driver = try Driver(args: [
          "swiftc", "-c", "-driver-filelist-threshold=0",
          "-enable-batch-mode", "-driver-batch-count", "1",
          "-output-file-map", file.path.pathString,
          "-module-name", "test", "/tmp/second.swift", "/tmp/main.swift"
        ])
        jobs = try driver.planBuild()
        XCTAssertEqual(getFileListElements(for: "-output-filelist", job: jobs[0]),
                       [.absolute(try .init(validating: "/tmp/build1/second.o")), .absolute(try .init(validating: "/tmp/build1/main.o"))])
        XCTAssertEqual(getFileListElements(for: "-index-unit-output-path-filelist", job: jobs[0]),
                       [.absolute(try .init(validating: "/tmp/build2/second.o")), .absolute(try .init(validating: "/tmp/build2/main.o"))])

        // 3. Multi-threaded WMO
        // a) without filelists
        driver = try Driver(args: [
          "swiftc", "-c", "-whole-module-optimization", "-num-threads", "2",
          "-output-file-map", file.path.pathString,
          "-module-name", "test", "/tmp/second.swift", "/tmp/main.swift"
        ])
        jobs = try driver.planBuild()
        XCTAssertTrue(jobs[0].commandLine.contains(subsequence: ["-o", .path(.absolute(try .init(validating: "/tmp/build1/second.o")))]))
        XCTAssertTrue(jobs[0].commandLine.contains(subsequence: ["-index-unit-output-path", .path(.absolute(try .init(validating: "/tmp/build2/second.o")))]))
        XCTAssertTrue(jobs[0].commandLine.contains(subsequence: ["-o", .path(.absolute(try .init(validating: "/tmp/build1/main.o")))]))
        XCTAssertTrue(jobs[0].commandLine.contains(subsequence: ["-index-unit-output-path", .path(.absolute(try .init(validating: "/tmp/build2/main.o")))]))

        // b) with filelists
        driver = try Driver(args: [
          "swiftc", "-c", "-driver-filelist-threshold=0",
          "-whole-module-optimization", "-num-threads", "2",
          "-output-file-map", file.path.pathString,
          "-module-name", "test", "/tmp/second.swift", "/tmp/main.swift"
        ])
        jobs = try driver.planBuild()
        XCTAssertEqual(getFileListElements(for: "-output-filelist", job: jobs[0]),
                       [.absolute(try .init(validating: "/tmp/build1/second.o")), .absolute(try .init(validating: "/tmp/build1/main.o"))])
        XCTAssertEqual(getFileListElements(for: "-index-unit-output-path-filelist", job: jobs[0]),
                       [.absolute(try .init(validating: "/tmp/build2/second.o")), .absolute(try .init(validating: "/tmp/build2/main.o"))])

        // 4. Index-file (single primary)
        driver = try Driver(args: [
          "swiftc", "-c", "-enable-batch-mode", "-driver-batch-count", "1",
          "-module-name", "test", "/tmp/second.swift", "/tmp/main.swift",
          "-index-file", "-index-file-path", "/tmp/second.swift",
          "-disable-batch-mode", "-o", "/tmp/build1/second.o",
          "-index-unit-output-path", "/tmp/build2/second.o"
        ])
        jobs = try driver.planBuild()
        XCTAssertTrue(jobs[0].commandLine.contains(subsequence: ["-o", .path(.absolute(try .init(validating: "/tmp/build1/second.o")))]))
        XCTAssertTrue(jobs[0].commandLine.contains(subsequence: ["-index-unit-output-path", .path(.absolute(try .init(validating: "/tmp/build2/second.o")))]))
      }
    }
  }

  func testMergeModuleEmittingDependencies() throws {
    var driver1 = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-module-name", "Foo", "-emit-dependencies", "-emit-module", "-serialize-diagnostics", "-driver-filelist-threshold=9999", "-no-emit-module-separately"])
    let plannedJobs = try driver1.planBuild().removingAutolinkExtractJobs()
    XCTAssertTrue(plannedJobs[0].kind == .compile)
    XCTAssertTrue(plannedJobs[1].kind == .compile)
    XCTAssertTrue(plannedJobs[2].kind == .mergeModule)
    XCTAssertTrue(plannedJobs[0].commandLine.contains(.flag("-emit-dependencies-path")))
    XCTAssertTrue(plannedJobs[0].commandLine.contains(.flag("-serialize-diagnostics-path")))
    XCTAssertTrue(plannedJobs[1].commandLine.contains(.flag("-emit-dependencies-path")))
    XCTAssertTrue(plannedJobs[1].commandLine.contains(.flag("-serialize-diagnostics-path")))
    XCTAssertFalse(plannedJobs[2].commandLine.contains(.flag("-emit-dependencies-path")))
    XCTAssertFalse(plannedJobs[2].commandLine.contains(.flag("-serialize-diagnostics-path")))
  }

  func testEmitModuleEmittingDependencies() throws {
    var driver1 = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-module-name", "Foo", "-emit-dependencies", "-emit-module", "-serialize-diagnostics", "-driver-filelist-threshold=9999", "-experimental-emit-module-separately"])
    let plannedJobs = try driver1.planBuild().removingAutolinkExtractJobs()
    XCTAssertEqual(plannedJobs.count, 3)
    XCTAssertTrue(plannedJobs[0].kind == .emitModule)
    // TODO: This check is disabled as per rdar://85253406
    // XCTAssertTrue(plannedJobs[0].commandLine.contains(.flag("-emit-dependencies-path")))
    XCTAssertTrue(plannedJobs[0].commandLine.contains(.flag("-serialize-diagnostics-path")))
  }

  func testEmitConstValues() throws {
    do { // Just single files
      var driver = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "baz.swift",
                                     "-module-name", "Foo", "-emit-const-values"])
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(plannedJobs.count, 4)
      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertTrue(plannedJobs[0].commandLine.contains("-emit-const-values-path"))
      XCTAssertTrue(plannedJobs[0].outputs.contains(where: { $0.type == .swiftConstValues }))
      XCTAssertEqual(plannedJobs[1].kind, .compile)
      XCTAssertTrue(plannedJobs[1].commandLine.contains("-emit-const-values-path"))
      XCTAssertTrue(plannedJobs[1].outputs.contains(where: { $0.type == .swiftConstValues }))
      XCTAssertEqual(plannedJobs[2].kind, .compile)
      XCTAssertTrue(plannedJobs[2].commandLine.contains("-emit-const-values-path"))
      XCTAssertTrue(plannedJobs[2].outputs.contains(where: { $0.type == .swiftConstValues }))
      XCTAssertEqual(plannedJobs[3].kind, .link)
    }

    do { // Just single files with emit-module
      var driver = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "baz.swift", "-emit-module",
                                     "-module-name", "Foo", "-emit-const-values"])
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(plannedJobs.count, 4)
      XCTAssertEqual(plannedJobs[0].kind, .emitModule)
      // Ensure the emit-module job does *not* contain this flag
      XCTAssertFalse(plannedJobs[0].commandLine.contains("-emit-const-values-path"))
      XCTAssertEqual(plannedJobs[1].kind, .compile)
      XCTAssertTrue(plannedJobs[1].commandLine.contains("-emit-const-values-path"))
      XCTAssertTrue(plannedJobs[1].outputs.contains(where: { $0.type == .swiftConstValues }))
      XCTAssertEqual(plannedJobs[2].kind, .compile)
      XCTAssertTrue(plannedJobs[2].commandLine.contains("-emit-const-values-path"))
      XCTAssertTrue(plannedJobs[2].outputs.contains(where: { $0.type == .swiftConstValues }))
      XCTAssertEqual(plannedJobs[3].kind, .compile)
      XCTAssertTrue(plannedJobs[3].commandLine.contains("-emit-const-values-path"))
      XCTAssertTrue(plannedJobs[3].outputs.contains(where: { $0.type == .swiftConstValues }))
    }

    do { // Batch
      var driver = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "baz.swift",
                                     "-enable-batch-mode","-driver-batch-size-limit", "2",
                                     "-module-name", "Foo", "-emit-const-values"])
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertTrue(plannedJobs[0].primaryInputs.map{ $0.file.description }.elementsEqual([rebase("foo.swift"),
                                                                                           rebase("bar.swift")]))
      XCTAssertTrue(plannedJobs[0].commandLine.contains("-emit-const-values-path"))
      XCTAssertEqual(plannedJobs[0].outputs.filter({ $0.type == .swiftConstValues }).count, 2)
      XCTAssertEqual(plannedJobs[1].kind, .compile)
      XCTAssertTrue(plannedJobs[1].primaryInputs.map{ $0.file.description }.elementsEqual([rebase("baz.swift")]))
      XCTAssertTrue(plannedJobs[1].commandLine.contains("-emit-const-values-path"))
      XCTAssertEqual(plannedJobs[1].outputs.filter({ $0.type == .swiftConstValues }).count, 1)
      XCTAssertEqual(plannedJobs[2].kind, .link)
    }

    try withTemporaryFile { fileMapFile in // Batch with output-file-map
      let outputMapContents: ByteString = """
        {
          "foo.swift": {
            "object": "/tmp/foo.build/foo.swift.o",
            "const-values": "/tmp/foo.build/foo.swiftconstvalues"
          },
          "bar.swift": {
            "object": "/tmp/foo.build/bar.swift.o",
            "const-values": "/tmp/foo.build/bar.swiftconstvalues"
          },
          "baz.swift": {
            "object": "/tmp/foo.build/baz.swift.o",
            "const-values": "/tmp/foo.build/baz.swiftconstvalues"
          }
        }
        """
      try localFileSystem.writeFileContents(fileMapFile.path, bytes: outputMapContents)
      var driver = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "baz.swift",
                                     "-enable-batch-mode","-driver-batch-size-limit", "2",
                                     "-module-name", "Foo", "-emit-const-values",
                                     "-output-file-map", fileMapFile.path.description])
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertTrue(plannedJobs[0].primaryInputs.map{ $0.file.description }.elementsEqual([rebase("foo.swift"),
                                                                                           rebase("bar.swift")]))
      XCTAssertTrue(plannedJobs[0].commandLine.contains(subsequence: [.flag("-emit-const-values-path"), .path(.absolute(try .init(validating: "/tmp/foo.build/foo.swiftconstvalues")))]))
      XCTAssertTrue(plannedJobs[0].commandLine.contains(subsequence: [.flag("-emit-const-values-path"), .path(.absolute(try .init(validating: "/tmp/foo.build/bar.swiftconstvalues")))]))
      XCTAssertEqual(plannedJobs[0].outputs.filter({ $0.type == .swiftConstValues }).count, 2)
      XCTAssertEqual(plannedJobs[1].kind, .compile)
      XCTAssertTrue(plannedJobs[1].primaryInputs.map{ $0.file.description }.elementsEqual([rebase("baz.swift")]))
      XCTAssertTrue(plannedJobs[1].commandLine.contains("-emit-const-values-path"))
      XCTAssertEqual(plannedJobs[1].outputs.filter({ $0.type == .swiftConstValues }).count, 1)
      XCTAssertTrue(plannedJobs[1].commandLine.contains(subsequence: [.flag("-emit-const-values-path"), .path(.absolute(try .init(validating: "/tmp/foo.build/baz.swiftconstvalues")))]))
      XCTAssertEqual(plannedJobs[2].kind, .link)
    }

    do { // WMO
      var driver = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "baz.swift",
                                     "-whole-module-optimization",
                                     "-module-name", "Foo", "-emit-const-values"])
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(plannedJobs.count, 2)
      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertEqual(plannedJobs[0].outputs.filter({ $0.type == .swiftConstValues }).count, 1)
      XCTAssertEqual(plannedJobs[1].kind, .link)
    }

    try withTemporaryFile { fileMapFile in // WMO with output-file-map
      let outputMapContents: ByteString = """
        {
          "": {
            "const-values": "/tmp/foo.build/foo.master.swiftconstvalues"
          },
          "foo.swift": {
            "object": "/tmp/foo.build/foo.swift.o",
            "const-values": "/tmp/foo.build/foo.swiftconstvalues"
          },
          "bar.swift": {
            "object": "/tmp/foo.build/bar.swift.o",
            "const-values": "/tmp/foo.build/bar.swiftconstvalues"
          },
          "baz.swift": {
            "object": "/tmp/foo.build/baz.swift.o",
            "const-values": "/tmp/foo.build/baz.swiftconstvalues"
          }
        }
        """
      try localFileSystem.writeFileContents(fileMapFile.path, bytes: outputMapContents)
      var driver = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "baz.swift",
                                     "-whole-module-optimization",
                                     "-module-name", "Foo", "-emit-const-values",
                                     "-output-file-map", fileMapFile.path.description])
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(plannedJobs.count, 2)
      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertEqual(plannedJobs[0].outputs.first(where: { $0.type == .swiftConstValues })?.file,
                     .absolute(try .init(validating: "/tmp/foo.build/foo.master.swiftconstvalues")))
      XCTAssertEqual(plannedJobs[1].kind, .link)
    }
  }

  func testEmitModuleSepratelyEmittingDiagnosticsWithOutputFileMap() throws {
    try withTemporaryDirectory { path in
      let outputFileMap = path.appending(component: "outputFileMap.json")
      try localFileSystem.writeFileContents(outputFileMap, bytes: """
        {
          "": {
            "emit-module-diagnostics": "/build/Foo-test.dia"
          }
        }
        """
      )
      var driver = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-module-name", "Foo", "-emit-module",
                                      "-serialize-diagnostics", "-experimental-emit-module-separately",
                                      "-output-file-map", outputFileMap.description])
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()

      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertTrue(plannedJobs[0].kind == .emitModule)
      XCTAssertTrue(plannedJobs[0].commandLine.contains(subsequence: [.flag("-serialize-diagnostics-path"), .path(.absolute(try .init(validating: "/build/Foo-test.dia")))]))
    }
  }

  func testReferenceDependencies() throws {
    var driver = try Driver(args: ["swiftc", "foo.swift", "-incremental"])
    let plannedJobs = try driver.planBuild()
    XCTAssertTrue(plannedJobs[0].kind == .compile)
    XCTAssertTrue(plannedJobs[0].commandLine.contains(.flag("-emit-reference-dependencies-path")))
  }

  func testDuplicateName() throws {
    assertDiagnostics { diagnosticsEngine, verify in
      _ = try? Driver(args: ["swiftc", "-c", "/foo.swift", "/foo.swift"], diagnosticsEngine: diagnosticsEngine)
      verify.expect(.error("filename \"foo.swift\" used twice: '/foo.swift' and '/foo.swift'"))
      verify.expect(.note("filenames are used to distinguish private declarations with the same name"))
    }

    assertDiagnostics { diagnosticsEngine, verify in
      _ = try? Driver(args: ["swiftc", "-c", "/foo.swift", "/foo/foo.swift"], diagnosticsEngine: diagnosticsEngine)
      verify.expect(.error("filename \"foo.swift\" used twice: '/foo.swift' and '/foo/foo.swift'"))
      verify.expect(.note("filenames are used to distinguish private declarations with the same name"))
    }
  }

  func testOutputFileMapStoring() throws {
    // Create sample OutputFileMap:

    // Rather than writing VirtualPath(path:...) over and over again, make strings, then fix it
    let stringyEntries: [String: [FileType: String]] = [
      "": [.swiftDeps: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/master.swiftdeps"],
      "foo.swift" : [
        .dependencies: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.d",
        .object: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.swift.o",
        .swiftModule: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo~partial.swiftmodule",
        .swiftDeps: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.swiftdeps"
        ]
    ]
    let pathyEntries = try Dictionary(uniqueKeysWithValues:
      stringyEntries.map { try
        (
          VirtualPath.intern(path: $0.key),
          Dictionary(uniqueKeysWithValues: $0.value.map { try ($0.key, VirtualPath.intern(path: $0.value))})
        )})
    let sampleOutputFileMap = OutputFileMap(entries: pathyEntries)

    try withTemporaryFile { file in
      try sampleOutputFileMap.store(fileSystem: localFileSystem, file: file.path, diagnosticEngine: DiagnosticsEngine())
      let contentsForDebugging = try localFileSystem.readFileContents(file.path).cString
      _ = contentsForDebugging
      let recoveredOutputFileMap = try OutputFileMap.load(fileSystem: localFileSystem, file: .absolute(file.path), diagnosticEngine: DiagnosticsEngine())
      XCTAssertEqual(sampleOutputFileMap, recoveredOutputFileMap)
    }
  }

  func testOutputFileMapResolving() throws {
    // Create sample OutputFileMap:

    let stringyEntries: [String: [FileType: String]] = [
      "": [.swiftDeps: "foo.build/master.swiftdeps"],
      "foo.swift" : [
        .dependencies: "foo.build/foo.d",
        .object: "foo.build/foo.swift.o",
        .swiftModule: "foo.build/foo~partial.swiftmodule",
        .swiftDeps: "foo.build/foo.swiftdeps"
      ]
    ]

    let root = localFileSystem.currentWorkingDirectory!.appending(components: "foo_root")

    let resolvedStringyEntries: [String: [FileType: String]] = [
      "": [.swiftDeps: root.appending(components: "foo.build", "master.swiftdeps").pathString],
      root.appending(component: "foo.swift").pathString : [
        .dependencies: root.appending(components: "foo.build", "foo.d").pathString,
        .object: root.appending(components: "foo.build", "foo.swift.o").pathString,
        .swiftModule: root.appending(components: "foo.build", "foo~partial.swiftmodule").pathString,
        .swiftDeps: root.appending(components: "foo.build", "foo.swiftdeps").pathString
      ]
    ]

    func outputFileMapFromStringyEntries(
      _ entries: [String: [FileType: String]]
    ) throws -> OutputFileMap {
      .init(entries: Dictionary(uniqueKeysWithValues: try entries.map { try (
        VirtualPath.intern(path: $0.key),
        $0.value.mapValues(VirtualPath.intern(path:))
      )}))
    }

    let sampleOutputFileMap =
      try outputFileMapFromStringyEntries(stringyEntries)
    let resolvedOutputFileMap = sampleOutputFileMap
      .resolveRelativePaths(relativeTo: root)
    let expectedOutputFileMap =
      try outputFileMapFromStringyEntries(resolvedStringyEntries)
    XCTAssertEqual(expectedOutputFileMap, resolvedOutputFileMap)
  }

  func testOutputFileMapRelativePathArg() throws {
    guard let cwd = localFileSystem.currentWorkingDirectory else {
      fatalError()
    }

    try withTemporaryDirectory(dir: cwd, removeTreeOnDeinit: true) { path in
      let outputFileMap = path.appending(component: "outputFileMap.json")
      try localFileSystem.writeFileContents(outputFileMap, bytes:
        """
        {
          "": {
            "swift-dependencies": "build/master.swiftdeps"
          },
          "main.swift": {
            "object": "build/main.o",
            "dependencies": "build/main.o.d"
          },
          "util.swift": {
            "object": "build/util.o",
            "dependencies": "build/util.o.d"
          }
        }
        """
      )
      let outputFileMapRelative = outputFileMap.relative(to: cwd).pathString
      // FIXME: Needs a better way to check that outputFileMap correctly loaded
      XCTAssertNoThrow(try Driver(args: [
        "swiftc",
        "-output-file-map", outputFileMapRelative,
        "main.swift", "util.swift",
      ]))
    }
  }

  func testResponseFileExpansion() throws {
    try withTemporaryDirectory { path in
      let diags = DiagnosticsEngine()
      let fooPath = path.appending(component: "foo.rsp")
      let barPath = path.appending(component: "bar.rsp")
#if os(Windows)
      try localFileSystem.writeFileContents(fooPath, bytes:
        .init("hello\nbye\n\"bye to you\"\n@\(barPath.nativePathString(escaped: true))".utf8)
      )
#else
      try localFileSystem.writeFileContents(fooPath, bytes:
        .init("hello\nbye\nbye\\ to\\ you\n@\(barPath.nativePathString(escaped: true))".utf8)
      )
#endif
      try localFileSystem.writeFileContents(barPath, bytes:
        .init("from\nbar\n@\(fooPath.nativePathString(escaped: true))".utf8)
      )
      let args = try Driver.expandResponseFiles(["swift", "compiler", "-Xlinker", "@loader_path", "@" + fooPath.pathString, "something"], fileSystem: localFileSystem, diagnosticsEngine: diags)
      XCTAssertEqual(args, ["swift", "compiler", "-Xlinker", "@loader_path", "hello", "bye", "bye to you", "from", "bar", "something"])
      XCTAssertEqual(diags.diagnostics.count, 1)
      XCTAssert(diags.diagnostics.first?.description.contains("is recursively expanded") ?? false)
    }
  }

  func testResponseFileExpansionRelativePathsInCWD() throws {
    try withTemporaryDirectory { path in
      guard let preserveCwd = localFileSystem.currentWorkingDirectory else {
        fatalError()
      }
      try localFileSystem.changeCurrentWorkingDirectory(to: path)
      defer { try! localFileSystem.changeCurrentWorkingDirectory(to: preserveCwd) }

      let diags = DiagnosticsEngine()
      let fooPath = path.appending(component: "foo.rsp")
      let barPath = path.appending(component: "bar.rsp")
#if os(Windows)
      try localFileSystem.writeFileContents(fooPath, bytes: "hello\nbye\n\"bye to you\"\n@bar.rsp")
#else
      try localFileSystem.writeFileContents(fooPath, bytes: "hello\nbye\nbye\\ to\\ you\n@bar.rsp")
#endif
      try localFileSystem.writeFileContents(barPath, bytes: "from\nbar\n@foo.rsp")

      let args = try Driver.expandResponseFiles(["swift", "compiler", "-Xlinker", "@loader_path", "@foo.rsp", "something"], fileSystem: localFileSystem, diagnosticsEngine: diags)
      XCTAssertEqual(args, ["swift", "compiler", "-Xlinker", "@loader_path", "hello", "bye", "bye to you", "from", "bar", "something"])
      XCTAssertEqual(diags.diagnostics.count, 1)
      XCTAssert(diags.diagnostics.first!.description.contains("is recursively expanded"))
    }
  }

  /// Tests that relative paths in response files are resolved based on the CWD, not the response file's location.
  func testResponseFileExpansionRelativePathsNotInCWD() throws {
    try withTemporaryDirectory { path in
      guard let preserveCwd = localFileSystem.currentWorkingDirectory else {
        fatalError()
      }
      try localFileSystem.changeCurrentWorkingDirectory(to: path)
      defer { try! localFileSystem.changeCurrentWorkingDirectory(to: preserveCwd) }

      try localFileSystem.createDirectory(path.appending(component: "subdir"))

      let diags = DiagnosticsEngine()
      let fooPath = path.appending(components: "subdir", "foo.rsp")
      let barPath = path.appending(components: "subdir", "bar.rsp")
#if os(Windows)
      try localFileSystem.writeFileContents(fooPath, bytes: "hello\nbye\n\"bye to you\"\n@subdir/bar.rsp")
#else
      try localFileSystem.writeFileContents(fooPath, bytes: "hello\nbye\nbye\\ to\\ you\n@subdir/bar.rsp")
#endif
      try localFileSystem.writeFileContents(barPath, bytes: "from\nbar\n@subdir/foo.rsp")

      let args = try Driver.expandResponseFiles(["swift", "compiler", "-Xlinker", "@loader_path", "@subdir/foo.rsp", "something"], fileSystem: localFileSystem, diagnosticsEngine: diags)
      XCTAssertEqual(args, ["swift", "compiler", "-Xlinker", "@loader_path", "hello", "bye", "bye to you", "from", "bar", "something"])
      XCTAssertEqual(diags.diagnostics.count, 1)
      XCTAssert(diags.diagnostics.first!.description.contains("is recursively expanded"))
    }
  }

  /// Tests how response files tokens such as spaces, comments, escaping characters and quotes, get parsed and expanded.
  func testResponseFileTokenization() throws {
    try withTemporaryDirectory { path  in
      let diags = DiagnosticsEngine()
      let fooPath = path.appending(component: "foo.rsp")
      let barPath = path.appending(component: "bar.rsp")
      let escapingPath = path.appending(component: "escaping.rsp")

#if os(Windows)
      try localFileSystem.writeFileContents(fooPath, bytes:
        .init(("""
        a\\b c\\\\d e\\\\\"f g\" h\\\"i j\\\\\\\"k \"lmn\" o pqr \"st \\\"u\" \\v"
        @\(barPath.nativePathString(escaped: true))
        """).utf8)
      )
      try localFileSystem.writeFileContents(barPath, bytes:
       .init((#"""
        -Xswiftc -use-ld=lld
        -Xcc -IS:\Library\sqlite-3.36.0\usr\include
        -Xlinker -LS:\Library\sqlite-3.36.0\usr\lib
        """#).utf8)
      )
      let args = try Driver.expandResponseFiles(["@\(fooPath.pathString)"], fileSystem: localFileSystem, diagnosticsEngine: diags)
      XCTAssertEqual(args, ["a\\b", "c\\\\d", "e\\f g", "h\"i", "j\\\"k", "lmn", "o", "pqr", "st \"u", "\\v", "-Xswiftc", "-use-ld=lld", "-Xcc", "-IS:\\Library\\sqlite-3.36.0\\usr\\include", "-Xlinker", "-LS:\\Library\\sqlite-3.36.0\\usr\\lib"])
#else
      try localFileSystem.writeFileContents(fooPath, bytes:
        .init((#"""
          Command1 --kkc
          //This is a comment
          // this is another comment
          but this is \\\\\a command
          @\#(barPath.nativePathString(escaped: true))
          @NotAFile
          -flag="quoted string with a \"quote\" inside" -another-flag
          """#
          + "\nthis  line\thas        lots \t  of    whitespace").utf8
        )
      )

      try localFileSystem.writeFileContents(barPath, bytes:
        #"""
        swift
        "rocks!"
        compiler
        -Xlinker

        @loader_path
        mkdir "Quoted Dir"
        cd Unquoted\ Dir
        // Bye!
        """#
      )

      try localFileSystem.writeFileContents(escapingPath, bytes:
        "swift\n--driver-mode=swiftc\n-v\r\n//comment\n\"the end\""
      )
      let args = try Driver.expandResponseFiles(["@" + fooPath.pathString], fileSystem: localFileSystem, diagnosticsEngine: diags)
      XCTAssertEqual(args, ["Command1", "--kkc", "but", "this", "is", #"\\a"#, "command", #"swift"#, "rocks!" ,"compiler", "-Xlinker", "@loader_path", "mkdir", "Quoted Dir", "cd", "Unquoted Dir", "@NotAFile", #"-flag=quoted string with a "quote" inside"#, "-another-flag", "this", "line", "has", "lots", "of", "whitespace"])
      let escapingArgs = try Driver.expandResponseFiles(["@" + escapingPath.pathString], fileSystem: localFileSystem, diagnosticsEngine: diags)
      XCTAssertEqual(escapingArgs, ["swift", "--driver-mode=swiftc", "-v","the end"])
#endif
    }
  }

  func testUsingResponseFiles() throws {
    let manyArgs = (1...20000).map { "-DTEST_\($0)" }
    // Needs response file
    do {
      var driver = try Driver(args: ["swift"] + manyArgs + ["/foo.swift"])
      let jobs = try driver.planBuild()
      XCTAssertTrue(jobs.count == 1 && jobs[0].kind == .interpret)
      let interpretJob = jobs[0]
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      let resolvedArgs: [String] = try resolver.resolveArgumentList(for: interpretJob)
      XCTAssertTrue(resolvedArgs.count == 3)
      XCTAssertEqual(resolvedArgs[1], "-frontend")
      XCTAssertEqual(resolvedArgs[2].first, "@")
      let responseFilePath = try AbsolutePath(validating: String(resolvedArgs[2].dropFirst()))
      let contents = try localFileSystem.readFileContents(responseFilePath).description
      XCTAssertTrue(contents.hasPrefix("\"-interpret\"\n\"/foo.swift\""))
      XCTAssertTrue(contents.contains("\"-D\"\n\"TEST_20000\""))
      XCTAssertTrue(contents.contains("\"-D\"\n\"TEST_1\""))
    }

    // Needs response file + disable override
    do {
      var driver = try Driver(args: ["swift"] + manyArgs + ["foo.swift"])
      let jobs = try driver.planBuild()
      XCTAssertTrue(jobs.count == 1 && jobs[0].kind == .interpret)
      let interpretJob = jobs[0]
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      let resolvedArgs: [String] = try resolver.resolveArgumentList(for: interpretJob, useResponseFiles: .disabled)
      XCTAssertFalse(resolvedArgs.contains { $0.hasPrefix("@") })
    }

    // Forced response file
    do {
      var driver = try Driver(args: ["swift"] + ["/foo.swift"])
      let jobs = try driver.planBuild()
      XCTAssertTrue(jobs.count == 1 && jobs[0].kind == .interpret)
      let interpretJob = jobs[0]
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      let resolvedArgs: [String] = try resolver.resolveArgumentList(for: interpretJob, useResponseFiles: .forced)
      XCTAssertTrue(resolvedArgs.count == 3)
      XCTAssertEqual(resolvedArgs[1], "-frontend")
      XCTAssertEqual(resolvedArgs[2].first, "@")
      let responseFilePath = try AbsolutePath(validating: String(resolvedArgs[2].dropFirst()))
      let contents = try localFileSystem.readFileContents(responseFilePath).description
      XCTAssertTrue(contents.hasPrefix("\"-interpret\"\n\"/foo.swift\""))
    }

    // No response file
    do {
      var driver = try Driver(args: ["swift"] + ["foo.swift"])
      let jobs = try driver.planBuild()
      XCTAssertTrue(jobs.count == 1 && jobs[0].kind == .interpret)
      let interpretJob = jobs[0]
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      let resolvedArgs: [String] = try resolver.resolveArgumentList(for: interpretJob)
      XCTAssertFalse(resolvedArgs.contains { $0.hasPrefix("@") })
    }
  }
    
  func testResponseFileDeterministicNaming() throws {
    #if !os(macOS)
    throw XCTSkip("Test assumes macOS response file quoting behavior")
    #endif
    do {
      let testJob = Job(moduleName: "Foo",
                        kind: .compile,
                        tool: .init(path: try AbsolutePath(validating: "/swiftc"), supportsResponseFiles: true),
                        commandLine: (1...20000).map { .flag("-DTEST_\($0)") },
                        inputs: [],
                        primaryInputs: [],
                        outputs: [])
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      let resolvedArgs: [String] = try resolver.resolveArgumentList(for: testJob)
      XCTAssertTrue(resolvedArgs.count == 3)
      XCTAssertEqual(resolvedArgs[2].first, "@")
      let responseFilePath = try AbsolutePath(validating: String(resolvedArgs[2].dropFirst()))
      XCTAssertEqual(responseFilePath.basename, "arguments-847d15e70d97df7c18033735497ca8dcc4441f461d5a9c2b764b127004524e81.resp")
    }
  }

  func testSpecificJobsResponseFiles() throws {
    // The jobs below often take large command lines (e.g., when passing a large number of Clang
    // modules to Swift). Ensure that they don't regress in their ability to pass response files
    // from the driver to the frontend.
    let manyArgs = (1...20000).map { "-DTEST_\($0)" }

    // Compile + separate emit module job
    do {
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      var driver = try Driver(
        args: ["swiftc", "-emit-module"] + manyArgs
          + ["-module-name", "foo", "foo.swift", "bar.swift"])
      let jobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(jobs.count, 3)
      XCTAssertEqual(Set(jobs.map { $0.kind }), Set([.emitModule, .compile]))

      let emitModuleJob = try jobs.findJob(.emitModule)
      let emitModuleResolvedArgs: [String] =
        try resolver.resolveArgumentList(for: emitModuleJob)
      XCTAssertEqual(emitModuleResolvedArgs.count, 3)
      XCTAssertEqual(emitModuleResolvedArgs[2].first, "@")

      let compileJobs = jobs.filter { $0.kind == .compile }
      XCTAssertEqual(compileJobs.count, 2)
      for compileJob in compileJobs {
        let compileResolvedArgs: [String] =
          try resolver.resolveArgumentList(for: compileJob)
        XCTAssertEqual(compileResolvedArgs.count, 3)
        XCTAssertEqual(compileResolvedArgs[2].first, "@")
      }
    }

    // Compile + no separate emit module job
    do {
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      var driver = try Driver(
        args: ["swiftc", "-emit-module", "-no-emit-module-separately"] + manyArgs
          + ["-module-name", "foo", "foo.swift", "bar.swift"])
      let jobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(jobs.count, 3)
      XCTAssertEqual(Set(jobs.map { $0.kind }), Set([.compile, .mergeModule]))

      let mergeModuleJob = try jobs.findJob(.mergeModule)
      let mergeModuleResolvedArgs: [String] =
        try resolver.resolveArgumentList(for: mergeModuleJob)
      XCTAssertEqual(mergeModuleResolvedArgs.count, 3)
      XCTAssertEqual(mergeModuleResolvedArgs[2].first, "@")

      let compileJobs = jobs.filter { $0.kind == .compile }
      XCTAssertEqual(compileJobs.count, 2)
      for compileJob in compileJobs {
        let compileResolvedArgs: [String] =
          try resolver.resolveArgumentList(for: compileJob)
        XCTAssertEqual(compileResolvedArgs.count, 3)
        XCTAssertEqual(compileResolvedArgs[2].first, "@")
      }
    }

    // Generate PCM (precompiled Clang module) job
    do {
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      var driver = try Driver(
        args: ["swiftc", "-emit-pcm"] + manyArgs + ["-module-name", "foo", "foo.modulemap"])
      let jobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(jobs.count, 1)
      XCTAssertEqual(jobs[0].kind, .generatePCM)

      let generatePCMJob = jobs[0]
      let generatePCMResolvedArgs: [String] =
        try resolver.resolveArgumentList(for: generatePCMJob)
      XCTAssertEqual(generatePCMResolvedArgs.count, 3)
      XCTAssertEqual(generatePCMResolvedArgs[2].first, "@")
    }
  }

  func testLinking() throws {
    var env = ProcessEnv.vars
    env["SWIFT_DRIVER_TESTS_ENABLE_EXEC_PATH_FALLBACK"] = "1"
    env["SWIFT_DRIVER_SWIFT_AUTOLINK_EXTRACT_EXEC"] = "/garbage/swift-autolink-extract"
    env["SWIFT_DRIVER_DSYMUTIL_EXEC"] = "/garbage/dsymutil"

    let commonArgs = ["swiftc", "foo.swift", "bar.swift",  "-module-name", "Test"]

    do {
      // macOS target
      var driver = try Driver(args: commonArgs + ["-emit-library", "-target", "x86_64-apple-macosx10.15", "-Onone", "-use-ld=foo", "-ld-path=/bar/baz"], env: env)
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(3, plannedJobs.count)
      XCTAssertFalse(plannedJobs.containsJob(.autolinkExtract))

      let linkJob = plannedJobs[2]
      XCTAssertEqual(linkJob.kind, .link)

      let cmd = linkJob.commandLine
      XCTAssertTrue(cmd.contains(.flag("-dynamiclib")))
      XCTAssertTrue(cmd.contains(.flag("-fuse-ld=foo")))
      XCTAssertTrue(cmd.contains(.joinedOptionAndPath("--ld-path=", try VirtualPath(path: "/bar/baz"))))
      XCTAssertTrue(cmd.contains(.flag("--target=x86_64-apple-macosx10.15")))
      XCTAssertEqual(linkJob.outputs[0].file, try toPath("libTest.dylib"))

      XCTAssertFalse(cmd.contains(.flag("-static")))
      XCTAssertFalse(cmd.contains(.flag("-shared")))
      // Handling of '-lobjc' is now in the Clang linker driver.
      XCTAssertFalse(cmd.contains(.flag("-lobjc")))
      XCTAssertTrue(cmd.contains(.flag("-O0")))
    }

    do {
      // .tbd inputs are passed down to the linker.
      var driver = try Driver(args: commonArgs + ["foo.dylib", "foo.tbd", "-target", "x86_64-apple-macosx10.15"], env: env)
      let plannedJobs = try driver.planBuild()
      let linkJob = plannedJobs[2]
      XCTAssertEqual(linkJob.kind, .link)
      let cmd = linkJob.commandLine
      XCTAssertTrue(cmd.contains(try toPathOption("foo.tbd")))
      XCTAssertTrue(cmd.contains(try toPathOption("foo.dylib")))
    }

    do {
      // iOS target
      var driver = try Driver(args: commonArgs + ["-emit-library", "-target", "arm64-apple-ios10.0"], env: env)
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(3, plannedJobs.count)
      XCTAssertFalse(plannedJobs.containsJob(.autolinkExtract))

      let linkJob = plannedJobs[2]
      XCTAssertEqual(linkJob.kind, .link)

      let cmd = linkJob.commandLine
      XCTAssertTrue(cmd.contains(.flag("-dynamiclib")))
      XCTAssertTrue(cmd.contains(.flag("--target=arm64-apple-ios10.0")))
      XCTAssertEqual(linkJob.outputs[0].file, try toPath("libTest.dylib"))

      XCTAssertFalse(cmd.contains(.flag("-static")))
      XCTAssertFalse(cmd.contains(.flag("-shared")))
    }

    do {
      // macOS catalyst target
      var driver = try Driver(args: commonArgs + ["-emit-library", "-target", "x86_64-apple-ios13.1-macabi"], env: env)
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(3, plannedJobs.count)
      XCTAssertFalse(plannedJobs.containsJob(.autolinkExtract))

      let linkJob = plannedJobs[2]
      XCTAssertEqual(linkJob.kind, .link)

      let cmd = linkJob.commandLine
      XCTAssertTrue(cmd.contains(.flag("-dynamiclib")))
      XCTAssertTrue(cmd.contains(.flag("--target=x86_64-apple-ios13.1-macabi")))
      XCTAssertEqual(linkJob.outputs[0].file, try toPath("libTest.dylib"))

      XCTAssertFalse(cmd.contains(.flag("-static")))
      XCTAssertFalse(cmd.contains(.flag("-shared")))
    }

    do {
      // Xlinker flags
      var driver = try Driver(args: commonArgs + ["-emit-library", "-L", "/tmp", "-Xlinker", "-w", "-target", "x86_64-apple-macosx10.15"], env: env)
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(3, plannedJobs.count)
      XCTAssertFalse(plannedJobs.containsJob(.autolinkExtract))

      let linkJob = plannedJobs[2]
      XCTAssertEqual(linkJob.kind, .link)

      let cmd = linkJob.commandLine
      XCTAssertTrue(cmd.contains(.flag("-dynamiclib")))
      XCTAssertTrue(cmd.contains(.flag("-w")))
      XCTAssertTrue(cmd.contains(.flag("-L")))
      XCTAssertTrue(cmd.contains(.path(.absolute(try .init(validating: "/tmp")))))
      XCTAssertEqual(linkJob.outputs[0].file, try toPath("libTest.dylib"))

      XCTAssertFalse(cmd.contains(.flag("-static")))
      XCTAssertFalse(cmd.contains(.flag("-shared")))
    }

    do {
      // -fobjc-link-runtime default
      var driver = try Driver(args: commonArgs + ["-emit-library", "-target", "x86_64-apple-macosx10.15"], env: env)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(3, plannedJobs.count)
      let linkJob = plannedJobs[2]
      XCTAssertEqual(linkJob.kind, .link)
      let cmd = linkJob.commandLine
      XCTAssertFalse(cmd.contains(.flag("-fobjc-link-runtime")))
    }

    do {
      // -fobjc-link-runtime enable
      var driver = try Driver(args: commonArgs + ["-emit-library", "-target", "x86_64-apple-macosx10.15", "-link-objc-runtime"], env: env)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(3, plannedJobs.count)
      let linkJob = plannedJobs[2]
      XCTAssertEqual(linkJob.kind, .link)
      let cmd = linkJob.commandLine
      XCTAssertTrue(cmd.contains(.flag("-fobjc-link-runtime")))
    }

    do {
      // -fobjc-link-runtime disable override
      var driver = try Driver(args: commonArgs + ["-emit-library", "-target", "x86_64-apple-macosx10.15", "-link-objc-runtime", "-no-link-objc-runtime"], env: env)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(3, plannedJobs.count)
      let linkJob = plannedJobs[2]
      XCTAssertEqual(linkJob.kind, .link)
      let cmd = linkJob.commandLine
      XCTAssertFalse(cmd.contains(.flag("-fobjc-link-runtime")))
    }

    do {
      // Xlinker flags
      // Ensure that Xlinker flags are passed as such to the clang linker invocation.
      var driver = try Driver(args: commonArgs + [
        "-emit-library", "-L", "/tmp", "-Xlinker", "-w",
        "-Xlinker", "-alias", "-Xlinker", "_foo_main", "-Xlinker", "_main",
        "-Xclang-linker", "foo", "-target", "x86_64-apple-macos12.0"], env: env)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)
      let linkJob = plannedJobs[2]
      let cmd = linkJob.commandLine
      XCTAssertTrue(cmd.contains(subsequence: [
        .flag("-Xlinker"), .flag("-alias"),
        .flag("-Xlinker"), .flag("_foo_main"),
        .flag("-Xlinker"), .flag("_main"),
        .flag("foo"),
      ]))
    }

    do {
      // Xlinker flags
      // Ensure that Xlinker flags are passed as such to the clang linker invocation.
      var driver = try Driver(args: commonArgs + ["-emit-library", "-L", "/tmp", "-Xlinker", "-w",
                                                  "-Xlinker", "-rpath=$ORIGIN", "-Xclang-linker", "foo",
                                                  "-target", "x86_64-unknown-linux"], env: env)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 4)
      let linkJob = plannedJobs[3]
      let cmd = linkJob.commandLine
      XCTAssertTrue(cmd.contains(subsequence: [.flag("-Xlinker"), .flag("-rpath=$ORIGIN"), .flag("foo")]))
    }

    do {
      // Xlinker flags
      // Ensure that Xlinker flags are passed as such to the clang linker invocation.
      try withTemporaryDirectory { path in
        try localFileSystem.writeFileContents(path.appending(components: "wasi", "static-executable-args.lnk")) {
          $0.send("garbage")
        }
        var driver = try Driver(args: commonArgs + ["-emit-executable", "-L", "/tmp", "-Xlinker", "--export-all",
                                                    "-Xlinker", "-E", "-Xclang-linker", "foo",
                                                    "-resource-dir", path.pathString,
                                                    "-target", "wasm32-unknown-wasi"], env: env)
        let plannedJobs = try driver.planBuild()
        XCTAssertEqual(plannedJobs.count, 4)
        let linkJob = plannedJobs[3]
        let cmd = linkJob.commandLine
        XCTAssertTrue(cmd.contains(subsequence: [
          .flag("-Xlinker"), .flag("--export-all"),
          .flag("-Xlinker"), .flag("-E"),
          .flag("foo")
        ]))
      }
    }

    do {
      var driver = try Driver(args: commonArgs + ["-emit-library", "-no-toolchain-stdlib-rpath",
                                                  "-target", "aarch64-unknown-linux"], env: env)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 4)
      let linkJob = plannedJobs[3]
      let cmd = linkJob.commandLine
      XCTAssertFalse(cmd.contains(subsequence: [.flag("-Xlinker"), .flag("-rpath"), .flag("-Xlinker")]))
    }

    do {
      // Object file inputs
      var driver = try Driver(args: commonArgs + ["baz.o", "-emit-library", "-target", "x86_64-apple-macosx10.15"], env: env)
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(3, plannedJobs.count)
      XCTAssertFalse(plannedJobs.containsJob(.autolinkExtract))

      let linkJob = plannedJobs[2]
      XCTAssertEqual(linkJob.kind, .link)

      let cmd = linkJob.commandLine
      XCTAssertTrue(linkJob.inputs.contains { matchTemporary($0.file, "foo.o") && $0.type == .object })
      XCTAssertTrue(linkJob.inputs.contains { matchTemporary($0.file, "bar.o") && $0.type == .object })
      XCTAssertTrue(linkJob.inputs.contains(.init(file: try toPath("baz.o").intern(), type: .object)))
      XCTAssertTrue(commandContainsTemporaryPath(cmd, "foo.o"))
      XCTAssertTrue(commandContainsTemporaryPath(cmd, "bar.o"))
      XCTAssertTrue(cmd.contains(try toPathOption("baz.o")))
    }

    do {
      // static linking
      var driver = try Driver(args: commonArgs + ["-emit-library", "-static", "-L", "/tmp", "-Xlinker", "-w", "-target", "x86_64-apple-macosx10.15"], env: env)
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertFalse(plannedJobs.containsJob(.autolinkExtract))

      let linkJob = plannedJobs[2]
      XCTAssertEqual(linkJob.kind, .link)

      let cmd = linkJob.commandLine
      XCTAssertTrue(cmd.contains(.flag("-static")))
      XCTAssertTrue(cmd.contains(.flag("-o")))
      XCTAssertTrue(commandContainsTemporaryPath(cmd, "foo.o"))
      XCTAssertTrue(commandContainsTemporaryPath(cmd, "bar.o"))
      XCTAssertEqual(linkJob.outputs[0].file, try toPath("libTest.a"))

      // The regular Swift driver doesn't pass Xlinker flags to the static
      // linker, so be consistent with this
      XCTAssertFalse(cmd.contains(.flag("-w")))
      XCTAssertFalse(cmd.contains(.flag("-L")))
      XCTAssertFalse(cmd.contains(.path(.absolute(try .init(validating: "/tmp")))))
      XCTAssertFalse(cmd.contains(.flag("-dylib")))
      XCTAssertFalse(cmd.contains(.flag("-shared")))
    }

    do {
      // static linking
      // Locating relevant libraries is dependent on being a macOS host
      #if os(macOS)
      var driver = try Driver(args: commonArgs + ["-emit-library", "-static", "-L", "/tmp", "-Xlinker", "-w", "-target", "x86_64-apple-macosx10.9", "-lto=llvm-full"], env: env)
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertFalse(plannedJobs.containsJob(.autolinkExtract))

      let linkJob = plannedJobs[2]
      XCTAssertEqual(linkJob.kind, .link)

      let cmd = linkJob.commandLine
      XCTAssertTrue(cmd.contains(.flag("-static")))
      XCTAssertTrue(cmd.contains(.flag("-o")))
      XCTAssertTrue(commandContainsTemporaryPath(cmd, "foo.bc"))
      XCTAssertTrue(commandContainsTemporaryPath(cmd, "bar.bc"))
      XCTAssertEqual(linkJob.outputs[0].file, try toPath("libTest.a"))

      // The regular Swift driver doesn't pass Xlinker flags to the static
      // linker, so be consistent with this
      XCTAssertFalse(cmd.contains(.flag("-w")))
      XCTAssertFalse(cmd.contains(.flag("-L")))
      XCTAssertFalse(cmd.contains(.path(.absolute(try .init(validating: "/tmp")))))
      XCTAssertFalse(cmd.contains(.flag("-dylib")))
      XCTAssertFalse(cmd.contains(.flag("-shared")))
      XCTAssertFalse(cmd.contains("-force_load"))
      XCTAssertFalse(cmd.contains("-platform_version"))
      XCTAssertFalse(cmd.contains("-lto_library"))
      XCTAssertFalse(cmd.contains("-syslibroot"))
      XCTAssertFalse(cmd.contains("-no_objc_category_merging"))
      #endif
    }

    do {
      // executable linking
      var driver = try Driver(args: commonArgs + ["-emit-executable", "-target", "x86_64-apple-macosx10.15"], env: env)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(3, plannedJobs.count)
      XCTAssertFalse(plannedJobs.containsJob(.autolinkExtract))

      let linkJob = plannedJobs[2]
      XCTAssertEqual(linkJob.kind, .link)

      let cmd = linkJob.commandLine
      XCTAssertTrue(cmd.contains(.flag("-o")))
      XCTAssertTrue(commandContainsTemporaryPath(cmd, "foo.o"))
      XCTAssertTrue(commandContainsTemporaryPath(cmd, "bar.o"))
      XCTAssertEqual(linkJob.outputs[0].file, try toPath("Test"))

      XCTAssertFalse(cmd.contains(.flag("-static")))
      XCTAssertFalse(cmd.contains(.flag("-dylib")))
      XCTAssertFalse(cmd.contains(.flag("-shared")))
    }

    do {
      // lto linking
      // Locating relevant libraries is dependent on being a macOS host
      #if os(macOS)
      var driver1 = try Driver(args: commonArgs + ["-emit-executable", "-target", "x86_64-apple-macosx10.15", "-lto=llvm-thin"], env: env)
      let plannedJobs1 = try driver1.planBuild()
      XCTAssertFalse(plannedJobs1.containsJob(.autolinkExtract))
      let linkJob1 = try plannedJobs1.findJob(.link)
      XCTAssertTrue(linkJob1.tool.name.contains("clang"))
      XCTAssertTrue(linkJob1.commandLine.contains(.flag("-flto=thin")))
      #endif

      var driver2 = try Driver(args: commonArgs + ["-emit-executable", "-O", "-target", "x86_64-unknown-linux", "-lto=llvm-thin"], env: env)
      let plannedJobs2 = try driver2.planBuild()
      XCTAssertFalse(plannedJobs2.containsJob(.autolinkExtract))
      let linkJob2 = try plannedJobs2.findJob(.link)
      XCTAssertTrue(linkJob2.tool.name.contains("clang"))
      XCTAssertTrue(linkJob2.commandLine.contains(.flag("-flto=thin")))
      XCTAssertTrue(linkJob2.commandLine.contains(.flag("-O3")))

      var driver3 = try Driver(args: commonArgs + ["-emit-executable", "-target", "x86_64-unknown-linux", "-lto=llvm-full"], env: env)
      let plannedJobs3 = try driver3.planBuild()
      XCTAssertFalse(plannedJobs3.containsJob(.autolinkExtract))

      let compileJob3 = try plannedJobs3.findJob(.compile)
      XCTAssertTrue(compileJob3.outputs.contains { $0.file.basename.hasSuffix(".bc") })

      let linkJob3 = try plannedJobs3.findJob(.link)
      XCTAssertTrue(linkJob3.tool.name.contains("clang"))
      XCTAssertTrue(linkJob3.commandLine.contains(.flag("-flto=full")))
    }

    do {
      var driver = try Driver(args: commonArgs + ["-emit-executable", "-Onone", "-emit-module", "-g", "-target", "x86_64-apple-macosx10.15"], env: env)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(5, plannedJobs.count)
      XCTAssertEqual(plannedJobs.map(\.kind), [.emitModule, .compile, .compile, .link, .generateDSYM])

      let linkJob = plannedJobs[3]
      XCTAssertEqual(linkJob.kind, .link)

      let cmd = linkJob.commandLine
      XCTAssertTrue(cmd.contains(.flag("-o")))
      XCTAssertTrue(commandContainsTemporaryPath(cmd, "foo.o"))
      XCTAssertTrue(commandContainsTemporaryPath(cmd, "bar.o"))
      XCTAssertTrue(cmd.contains(.joinedOptionAndPath("-Wl,-add_ast_path,", try toPath("Test.swiftmodule"))))
      XCTAssertTrue(cmd.contains(.flag("-O0")))
      XCTAssertEqual(linkJob.outputs[0].file, try toPath("Test"))

      XCTAssertFalse(cmd.contains(.flag("-static")))
      XCTAssertFalse(cmd.contains(.flag("-dylib")))
      XCTAssertFalse(cmd.contains(.flag("-shared")))
    }

    do {
      // linux target
      var driver = try Driver(args: commonArgs + ["-emit-library", "-target", "x86_64-unknown-linux"], env: env)
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 4)

      let autolinkExtractJob = plannedJobs[2]
      XCTAssertEqual(autolinkExtractJob.kind, .autolinkExtract)

      let autolinkCmd = autolinkExtractJob.commandLine
      XCTAssertTrue(commandContainsTemporaryPath(autolinkCmd, "foo.o"))
      XCTAssertTrue(commandContainsTemporaryPath(autolinkCmd, "bar.o"))
      XCTAssertTrue(commandContainsTemporaryPath(autolinkCmd, "Test.autolink"))

      let linkJob = plannedJobs[3]
      XCTAssertEqual(linkJob.kind, .link)
      let cmd = linkJob.commandLine
      XCTAssertTrue(cmd.contains(.flag("-o")))
      XCTAssertTrue(cmd.contains(.flag("-shared")))
      XCTAssertTrue(commandContainsTemporaryPath(cmd, "foo.o"))
      XCTAssertTrue(commandContainsTemporaryPath(cmd, "bar.o"))
      XCTAssertTrue(commandContainsTemporaryResponsePath(cmd, "Test.autolink"))
      XCTAssertEqual(linkJob.outputs[0].file, try toPath("libTest.so"))

      XCTAssertFalse(cmd.contains(.flag("-dylib")))
      XCTAssertFalse(cmd.contains(.flag("-static")))
    }

    do {
      // Linux shared objects (.so) are not offered to autolink-extract
      try withTemporaryDirectory { path in
        try localFileSystem.writeFileContents(
          path.appending(components: "libEmpty.so"), bytes:
            """
                /* empty */
            """
            )

        var driver = try Driver(args: commonArgs + ["-emit-executable", "-target", "x86_64-unknown-linux", "libEmpty.so"], env: env)
        let plannedJobs = try driver.planBuild()

        XCTAssertEqual(plannedJobs.count, 4)

        let autolinkExtractJob = plannedJobs[2]
        XCTAssertEqual(autolinkExtractJob.kind,.autolinkExtract)

        let autolinkCmd = autolinkExtractJob.commandLine
        XCTAssertTrue(commandContainsTemporaryPath(autolinkCmd, "foo.o"))
        XCTAssertTrue(commandContainsTemporaryPath(autolinkCmd, "bar.o"))
        XCTAssertTrue(commandContainsTemporaryPath(autolinkCmd, "Test.autolink"))
        XCTAssertFalse(
          autolinkCmd.contains {
            guard case .path(let path) = $0 else { return false }
            if case .relative(let p) = path, p.basename == "libEmpty.so" { return true }
            return false
          }
        )
      }
    }

    do {
      // static linux linking
      var driver = try Driver(args: commonArgs + ["-emit-library", "-static", "-target", "x86_64-unknown-linux"], env: env)
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 4)

      let autolinkExtractJob = plannedJobs[2]
      XCTAssertEqual(autolinkExtractJob.kind, .autolinkExtract)

      let autolinkCmd = autolinkExtractJob.commandLine
      XCTAssertTrue(commandContainsTemporaryPath(autolinkCmd, "foo.o"))
      XCTAssertTrue(commandContainsTemporaryPath(autolinkCmd, "bar.o"))
      XCTAssertTrue(commandContainsTemporaryPath(autolinkCmd, "Test.autolink"))

      let linkJob = plannedJobs[3]
      let cmd = linkJob.commandLine
      // we'd expect "ar crs libTest.a foo.o bar.o"
      XCTAssertTrue(cmd.contains(.flag("crs")))
      XCTAssertTrue(commandContainsTemporaryPath(cmd, "foo.o"))
      XCTAssertTrue(commandContainsTemporaryPath(cmd, "bar.o"))
      XCTAssertEqual(linkJob.outputs[0].file, try toPath("libTest.a"))

      XCTAssertFalse(cmd.contains(.flag("-o")))
      XCTAssertFalse(cmd.contains(.flag("-dylib")))
      XCTAssertFalse(cmd.contains(.flag("-static")))
      XCTAssertFalse(cmd.contains(.flag("-shared")))
      XCTAssertFalse(cmd.contains(.flag("--start-group")))
      XCTAssertFalse(cmd.contains(.flag("--end-group")))
    }

    // /usr/lib/swift_static/linux/static-stdlib-args.lnk is required for static
    // linking on Linux, but is not present in macOS toolchains
    #if os(Linux)
    do {
      // executable linking linux static stdlib
      var driver = try Driver(args: commonArgs + ["-emit-executable", "-Osize", "-static-stdlib", "-target", "x86_64-unknown-linux"], env: env)
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 4)

      let autolinkExtractJob = plannedJobs[2]
      XCTAssertEqual(autolinkExtractJob.kind, .autolinkExtract)

      let autolinkCmd = autolinkExtractJob.commandLine
      XCTAssertTrue(commandContainsTemporaryPath(autolinkCmd, "foo.o"))
      XCTAssertTrue(commandContainsTemporaryPath(autolinkCmd, "bar.o"))
      XCTAssertTrue(commandContainsTemporaryPath(autolinkCmd, "Test.autolink"))

      let linkJob = plannedJobs[3]
      let cmd = linkJob.commandLine
      XCTAssertTrue(cmd.contains(.flag("-o")))
      XCTAssertTrue(commandContainsTemporaryPath(cmd, "foo.o"))
      XCTAssertTrue(commandContainsTemporaryPath(cmd, "bar.o"))
      XCTAssertTrue(cmd.contains(.flag("--start-group")))
      XCTAssertTrue(cmd.contains(.flag("--end-group")))
      XCTAssertTrue(cmd.contains(.flag("-Os")))
      XCTAssertEqual(linkJob.outputs[0].file, try toPath("Test"))

      XCTAssertFalse(cmd.contains(.flag("-static")))
      XCTAssertFalse(cmd.contains(.flag("-dylib")))
      XCTAssertFalse(cmd.contains(.flag("-shared")))
    }

    do {
      // executable linking linux static stdlib with musl
      var driver = try Driver(args: commonArgs + [
        "-emit-executable", "-Osize", "-static-stdlib", "-static-executable", "-target", "x86_64-unknown-linux-musl"
      ], env: env)
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 4)

      let autolinkExtractJob = plannedJobs[2]
      XCTAssertEqual(autolinkExtractJob.kind, .autolinkExtract)

      let autolinkCmd = autolinkExtractJob.commandLine
      XCTAssertTrue(commandContainsTemporaryPath(autolinkCmd, "foo.o"))
      XCTAssertTrue(commandContainsTemporaryPath(autolinkCmd, "bar.o"))
      XCTAssertTrue(commandContainsTemporaryPath(autolinkCmd, "Test.autolink"))

      let linkJob = plannedJobs[3]
      let cmd = linkJob.commandLine
      XCTAssertTrue(cmd.contains(.flag("-o")))
      XCTAssertTrue(commandContainsTemporaryPath(cmd, "foo.o"))
      XCTAssertTrue(commandContainsTemporaryPath(cmd, "bar.o"))
      XCTAssertTrue(cmd.contains(.flag("--start-group")))
      XCTAssertTrue(cmd.contains(.flag("--end-group")))
      XCTAssertTrue(cmd.contains(.flag("-Os")))
      print("Static stdlib with musl link job: \(cmd.joinedUnresolvedArguments)")
      //XCTAssertTrue(cmd.contains(.flag("-static")))
      XCTAssertEqual(linkJob.outputs[0].file, try toPath("Test"))

      XCTAssertFalse(cmd.contains(.flag("-dylib")))
      XCTAssertFalse(cmd.contains(.flag("-shared")))
    }
    #endif

    do {
      // static Wasm linking
      var driver = try Driver(args: commonArgs + ["-emit-library", "-static", "-target", "wasm32-unknown-wasi"], env: env)
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 4)

      let autolinkExtractJob = plannedJobs[2]
      XCTAssertEqual(autolinkExtractJob.kind, .autolinkExtract)

      let autolinkCmd = autolinkExtractJob.commandLine
      XCTAssertTrue(commandContainsTemporaryPath(autolinkCmd, "foo.o"))
      XCTAssertTrue(commandContainsTemporaryPath(autolinkCmd, "bar.o"))
      XCTAssertTrue(commandContainsTemporaryPath(autolinkCmd, "Test.autolink"))

      let linkJob = plannedJobs[3]
      let cmd = linkJob.commandLine
      // we'd expect "ar crs libTest.a foo.o bar.o"
      XCTAssertTrue(cmd.contains(.flag("crs")))
      XCTAssertTrue(commandContainsTemporaryPath(cmd, "foo.o"))
      XCTAssertTrue(commandContainsTemporaryPath(cmd, "bar.o"))
      XCTAssertEqual(linkJob.outputs[0].file, try toPath("libTest.a"))

      XCTAssertFalse(cmd.contains(.flag("-o")))
      XCTAssertFalse(cmd.contains(.flag("-dylib")))
      XCTAssertFalse(cmd.contains(.flag("-static")))
      XCTAssertFalse(cmd.contains(.flag("-shared")))
    }

    do {
      try withTemporaryDirectory { path in
        try localFileSystem.writeFileContents(path.appending(components: "wasi", "static-executable-args.lnk")) {
          $0.send("garbage")
        }
        // Wasm executable linking
        var driver = try Driver(args: commonArgs + ["-emit-executable", "-Ounchecked",
                                                    "-target", "wasm32-unknown-wasi",
                                                    "-resource-dir", path.pathString,
                                                    "-sdk", "/sdk/path"], env: env)
        let plannedJobs = try driver.planBuild()

        XCTAssertEqual(plannedJobs.count, 4)

        let autolinkExtractJob = plannedJobs[2]
        XCTAssertEqual(autolinkExtractJob.kind, .autolinkExtract)

        let autolinkCmd = autolinkExtractJob.commandLine
        XCTAssertTrue(commandContainsTemporaryPath(autolinkCmd, "foo.o"))
        XCTAssertTrue(commandContainsTemporaryPath(autolinkCmd, "bar.o"))
        XCTAssertTrue(commandContainsTemporaryPath(autolinkCmd, "Test.autolink"))

        let linkJob = plannedJobs[3]
        let cmd = linkJob.commandLine
        XCTAssertTrue(cmd.contains(subsequence: ["-target", "wasm32-unknown-wasi"]))
        XCTAssertTrue(cmd.contains(subsequence: ["--sysroot", .path(.absolute(try .init(validating: "/sdk/path")))]))
        XCTAssertTrue(cmd.contains(.path(.absolute(path.appending(components: "wasi", "wasm32", "swiftrt.o")))))
        XCTAssertTrue(commandContainsTemporaryPath(cmd, "foo.o"))
        XCTAssertTrue(commandContainsTemporaryPath(cmd, "bar.o"))
        XCTAssertTrue(commandContainsTemporaryResponsePath(cmd, "Test.autolink"))
        XCTAssertTrue(cmd.contains(.responseFilePath(.absolute(path.appending(components: "wasi", "static-executable-args.lnk")))))
        XCTAssertTrue(cmd.contains(subsequence: [.flag("-Xlinker"), .flag("--global-base=4096")]))
        XCTAssertTrue(cmd.contains(.flag("-O3")))
        XCTAssertEqual(linkJob.outputs[0].file, try toPath("Test"))

        XCTAssertFalse(cmd.contains(.flag("-dylib")))
        XCTAssertFalse(cmd.contains(.flag("-shared")))
      }
    }

    do {
      // Linker flags with and without space
      var driver = try Driver(args: commonArgs + ["-lsomelib","-l","otherlib"], env: env)
      let plannedJobs = try driver.planBuild()
      let cmd = plannedJobs.last!.commandLine
      XCTAssertTrue(cmd.contains(.flag("-lsomelib")))
      XCTAssertTrue(cmd.contains(.flag("-lotherlib")))
    }

    do {
      // The Android NDK only uses the lld linker now
      var driver = try Driver(args: commonArgs + ["-emit-library", "-target", "aarch64-unknown-linux-android24", "-use-ld=lld"], env: env)
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
      let lastJob = plannedJobs.last!
      XCTAssertTrue(lastJob.tool.name.contains("clang"))
      XCTAssertTrue(lastJob.commandLine.contains(.flag("-fuse-ld=lld")))
    }
  }

  func testWebAssemblyUnsupportedFeatures() throws {
    var env = ProcessEnv.vars
    env["SWIFT_DRIVER_SWIFT_AUTOLINK_EXTRACT_EXEC"] = "/garbage/swift-autolink-extract"
    do {
      var driver = try Driver(args: ["swift", "-target", "wasm32-unknown-wasi", "foo.swift"], env: env)
      XCTAssertThrowsError(try driver.planBuild()) {
        guard case WebAssemblyToolchain.Error.interactiveModeUnsupportedForTarget("wasm32-unknown-wasi") = $0 else {
          XCTFail()
          return
        }
      }
    }

    do {
      var driver = try Driver(args: ["swiftc", "-target", "wasm32-unknown-wasi", "-emit-library", "foo.swift"], env: env)
      XCTAssertThrowsError(try driver.planBuild()) {
        guard case WebAssemblyToolchain.Error.dynamicLibrariesUnsupportedForTarget("wasm32-unknown-wasi") = $0 else {
          XCTFail()
          return
        }
      }
    }

    do {
      var driver = try Driver(args: ["swiftc", "-target", "wasm32-unknown-wasi", "-no-static-executable", "foo.swift"], env: env)
      XCTAssertThrowsError(try driver.planBuild()) {
        guard case WebAssemblyToolchain.Error.dynamicLibrariesUnsupportedForTarget("wasm32-unknown-wasi") = $0 else {
          XCTFail()
          return
        }
      }
    }

    do {
      XCTAssertThrowsError(try Driver(args: ["swiftc", "-target", "wasm32-unknown-wasi", "foo.swift", "-sanitize=thread"], env: env)) {
        guard case WebAssemblyToolchain.Error.sanitizersUnsupportedForTarget("wasm32-unknown-wasi") = $0 else {
          XCTFail()
          return
        }
      }
    }
  }

  private func clangPathInActiveXcode() throws -> AbsolutePath? {
#if !os(macOS)
    return nil
#else
    let process = Process(arguments: ["xcrun", "-toolchain", "default", "-f", "clang"])
    try process.launch()
    let result = try process.waitUntilExit()
    guard result.exitStatus == .terminated(code: EXIT_SUCCESS) else { return nil }
    guard let path = String(bytes: try result.output.get(), encoding: .utf8) else { return nil }
    return path.isEmpty ? nil : try AbsolutePath(validating: path.spm_chomp())
#endif
  }

  func testCompatibilityLibs() throws {
    var env = ProcessEnv.vars
    env["SWIFT_DRIVER_TESTS_ENABLE_EXEC_PATH_FALLBACK"] = "1"
    try withTemporaryDirectory { path in
      let path5_0Mac = path.appending(components: "macosx", "libswiftCompatibility50.a")
      let path5_1Mac = path.appending(components: "macosx", "libswiftCompatibility51.a")
      let pathDynamicReplacementsMac = path.appending(components: "macosx", "libswiftCompatibilityDynamicReplacements.a")
      let path5_0iOS = path.appending(components: "iphoneos", "libswiftCompatibility50.a")
      let path5_1iOS = path.appending(components: "iphoneos", "libswiftCompatibility51.a")
      let pathDynamicReplacementsiOS = path.appending(components: "iphoneos", "libswiftCompatibilityDynamicReplacements.a")
      let pathCompatibilityPacksMac = path.appending(components: "macosx", "libswiftCompatibilityPacks.a")

      for compatibilityLibPath in [path5_0Mac, path5_1Mac,
                                   pathDynamicReplacementsMac, path5_0iOS,
                                   path5_1iOS, pathDynamicReplacementsiOS,
                                   pathCompatibilityPacksMac] {
        try localFileSystem.createDirectory(compatibilityLibPath.parentDirectory, recursive: true)
        try localFileSystem.writeFileContents(compatibilityLibPath, bytes: "Empty")
      }
      let commonArgs = ["swiftc", "foo.swift", "bar.swift",  "-module-name", "Test", "-resource-dir", path.pathString]

      do {
        var driver = try Driver(args: commonArgs + ["-target", "x86_64-apple-macosx10.14"], env: env)
        let plannedJobs = try driver.planBuild()

        XCTAssertEqual(3, plannedJobs.count)
        let linkJob = plannedJobs[2]
        XCTAssertEqual(linkJob.kind, .link)
        let cmd = linkJob.commandLine

        XCTAssertTrue(cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(path5_0Mac))]))
        XCTAssertTrue(cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(path5_1Mac))]))
        XCTAssertTrue(cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(pathDynamicReplacementsMac))]))

        XCTAssertFalse(cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(pathCompatibilityPacksMac))]))
        XCTAssertTrue(cmd.contains(subsequence: [.path(.absolute(pathCompatibilityPacksMac))]))
      }

      do {
        var driver = try Driver(args: commonArgs + ["-target", "x86_64-apple-macosx10.15.1"], env: env)
        let plannedJobs = try driver.planBuild()

        XCTAssertEqual(3, plannedJobs.count)
        let linkJob = plannedJobs[2]
        XCTAssertEqual(linkJob.kind, .link)
        let cmd = linkJob.commandLine

        XCTAssertFalse(cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(path5_0Mac))]))
        XCTAssertTrue(cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(path5_1Mac))]))
        XCTAssertFalse(cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(pathDynamicReplacementsMac))]))

        XCTAssertFalse(cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(pathCompatibilityPacksMac))]))
        XCTAssertTrue(cmd.contains(subsequence: [.path(.absolute(pathCompatibilityPacksMac))]))
      }

      do {
        var driver = try Driver(args: commonArgs + ["-target", "x86_64-apple-macosx10.15.4"], env: env)
        let plannedJobs = try driver.planBuild()

        XCTAssertEqual(3, plannedJobs.count)
        let linkJob = plannedJobs[2]
        XCTAssertEqual(linkJob.kind, .link)
        let cmd = linkJob.commandLine

        XCTAssertFalse(cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(path5_0Mac))]))
        XCTAssertFalse(cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(path5_1Mac))]))
        XCTAssertFalse(cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(pathDynamicReplacementsMac))]))

        XCTAssertFalse(cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(pathCompatibilityPacksMac))]))
        XCTAssertTrue(cmd.contains(subsequence: [.path(.absolute(pathCompatibilityPacksMac))]))
      }

      do {
        var driver = try Driver(args: commonArgs + ["-target", "x86_64-apple-macosx10.15.4", "-runtime-compatibility-version", "5.0"], env: env)
        let plannedJobs = try driver.planBuild()

        XCTAssertEqual(3, plannedJobs.count)
        let linkJob = plannedJobs[2]
        XCTAssertEqual(linkJob.kind, .link)
        let cmd = linkJob.commandLine

        XCTAssertTrue(cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(path5_0Mac))]))
        XCTAssertTrue(cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(path5_1Mac))]))
        XCTAssertTrue(cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(pathDynamicReplacementsMac))]))

        XCTAssertFalse(cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(pathCompatibilityPacksMac))]))
        XCTAssertTrue(cmd.contains(subsequence: [.path(.absolute(pathCompatibilityPacksMac))]))
      }

      do {
        var driver = try Driver(args: commonArgs + ["-target", "arm64-apple-ios13.0"], env: env)
        let plannedJobs = try driver.planBuild()

        XCTAssertEqual(3, plannedJobs.count)
        let linkJob = plannedJobs[2]
        XCTAssertEqual(linkJob.kind, .link)
        let cmd = linkJob.commandLine

        XCTAssertFalse(cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(path5_0iOS))]))
        XCTAssertTrue(cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(path5_1iOS))]))
        XCTAssertFalse(cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(pathDynamicReplacementsiOS))]))
      }

      do {
        var driver = try Driver(args: commonArgs + ["-target", "arm64-apple-ios12.0"], env: env)
        let plannedJobs = try driver.planBuild()

        XCTAssertEqual(3, plannedJobs.count)
        let linkJob = plannedJobs[2]
        XCTAssertEqual(linkJob.kind, .link)
        let cmd = linkJob.commandLine

        XCTAssertTrue(cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(path5_0iOS))]))
        XCTAssertTrue(cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(path5_1iOS))]))
        XCTAssertTrue(cmd.contains(subsequence: [.flag("-force_load"), .path(.absolute(pathDynamicReplacementsiOS))]))
      }
    }
  }

  func testSanitizerRecoverArgs() throws {
    let commonArgs = ["swiftc", "foo.swift", "bar.swift",]
    do {
      // address sanitizer + address sanitizer recover
      var driver = try Driver(args: commonArgs + ["-sanitize=address", "-sanitize-recover=address"])
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()

      XCTAssertEqual(plannedJobs.count, 3)

      let compileJob = plannedJobs[0]
      let compileCmd = compileJob.commandLine
      XCTAssertTrue(compileCmd.contains(.flag("-sanitize=address")))
      XCTAssertTrue(compileCmd.contains(.flag("-sanitize-recover=address")))
    }
    do {
      // invalid sanitize recover arg
      try assertDriverDiagnostics(args: commonArgs + ["-sanitize-recover=foo"]) {
        $1.expect(.error("invalid value 'foo' in '-sanitize-recover='"))
      }
    }
    do {
      // only address is supported
      try assertDriverDiagnostics(args: commonArgs + ["-sanitize-recover=thread"]) {
        $1.expect(.error("unsupported argument 'thread' to option '-sanitize-recover='"))
      }
    }
    do {
      // only address is supported
      try assertDriverDiagnostics(args: commonArgs + ["-sanitize-recover=scudo"]) {
        $1.expect(.error("unsupported argument 'scudo' to option '-sanitize-recover='"))
      }
    }
    do {
      // invalid sanitize recover arg
      try assertDriverDiagnostics(args: commonArgs + ["-sanitize-recover=undefined"]) {
        $1.expect(.error("unsupported argument 'undefined' to option '-sanitize-recover='"))
      }
    }
    do {
      // no sanitizer + address sanitizer recover
      try assertDriverDiagnostics(args: commonArgs + ["-sanitize-recover=address"]) {
        $1.expect(.warning("option '-sanitize-recover=address' has no effect when 'address' sanitizer is disabled. Use -sanitize=address to enable the sanitizer"))
      }
    }
    do {
      // thread sanitizer + address sanitizer recover
      try assertDriverDiagnostics(args: commonArgs + ["-sanitize=thread", "-sanitize-recover=address"]) {
      #if os(Windows)
        $1.expect(.error("thread sanitizer is unavailable on target 'x86_64-unknown-windows-msvc'"))
      #endif
        $1.expect(.warning("option '-sanitize-recover=address' has no effect when 'address' sanitizer is disabled. Use -sanitize=address to enable the sanitizer"))
      }
    }
    // "-sanitize=undefined" is not available on x86_64-unknown-linux-gnu
    #if os(macOS)
    do {
      // multiple sanitizers separately
      try assertDriverDiagnostics(args: commonArgs + ["-sanitize=undefined", "-sanitize=address", "-sanitize-recover=address"]) {
        $1.forbidUnexpected(.error, .warning)
      }
    }
    do {
      // comma sanitizer + address sanitizer recover together
      try assertDriverDiagnostics(args: commonArgs + ["-sanitize=undefined,address", "-sanitize-recover=address"]) {
        $1.forbidUnexpected(.error, .warning)
      }
    }
    #endif
  }

  func testSanitizerArgs() throws {
    let commonArgs = [
      "swiftc", "foo.swift", "bar.swift",
      "-emit-executable", "-target", "x86_64-apple-macosx10.9",
      "-module-name", "Test"
    ]
  // FIXME: This doesn't work on Linux.
  #if os(macOS)
    do {
      // address sanitizer
      var driver = try Driver(args: commonArgs + ["-sanitize=address"])
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 3)

      let compileJob = plannedJobs[0]
      let compileCmd = compileJob.commandLine
      XCTAssertTrue(compileCmd.contains(.flag("-sanitize=address")))

      let linkJob = plannedJobs[2]
      let linkCmd = linkJob.commandLine
      XCTAssertTrue(linkCmd.contains(.flag("-fsanitize=address")))
    }

    do {
      // address sanitizer on a dylib
      var driver = try Driver(args: commonArgs + ["-sanitize=address", "-emit-library"])
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 3)

      let compileJob = plannedJobs[0]
      let compileCmd = compileJob.commandLine
      XCTAssertTrue(compileCmd.contains(.flag("-sanitize=address")))

      let linkJob = plannedJobs[2]
      let linkCmd = linkJob.commandLine
      XCTAssertTrue(linkCmd.contains(.flag("-fsanitize=address")))
    }

    do {
      // *no* address sanitizer on a static lib
      var driver = try Driver(args: commonArgs + ["-sanitize=address", "-emit-library", "-static"])
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 3)

      let linkJob = plannedJobs[2]
      let linkCmd = linkJob.commandLine
      XCTAssertFalse(linkCmd.contains(.flag("-fsanitize=address")))
    }

    do {
      // thread sanitizer
      var driver = try Driver(args: commonArgs + ["-sanitize=thread"])
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 3)

      let compileJob = plannedJobs[0]
      let compileCmd = compileJob.commandLine
      XCTAssertTrue(compileCmd.contains(.flag("-sanitize=thread")))

      let linkJob = plannedJobs[2]
      let linkCmd = linkJob.commandLine
      XCTAssertTrue(linkCmd.contains(.flag("-fsanitize=thread")))
    }

    do {
      // undefined behavior sanitizer
      var driver = try Driver(args: commonArgs + ["-sanitize=undefined"])
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 3)

      let compileJob = plannedJobs[0]
      let compileCmd = compileJob.commandLine
      XCTAssertTrue(compileCmd.contains(.flag("-sanitize=undefined")))

      let linkJob = plannedJobs[2]
      let linkCmd = linkJob.commandLine
      XCTAssertTrue(linkCmd.contains(.flag("-fsanitize=undefined")))
    }

    // FIXME: This test will fail when run on macOS, because the driver uses
    //        the existence of the runtime support libraries to determine if
    //        a sanitizer is supported. Until we allow cross-compiling with
    //        sanitizers, we'll need to disable this test on macOS
    #if os(Linux)
    do {
      // linux multiple sanitizers
      var driver = try Driver(
        args: commonArgs + [
          "-target", "x86_64-unknown-linux",
          "-sanitize=address", "-sanitize=undefined"
        ]
      )
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 4)

      let compileJob = plannedJobs[0]
      let compileCmd = compileJob.commandLine
      XCTAssertTrue(compileCmd.contains(.flag("-sanitize=address")))
      XCTAssertTrue(compileCmd.contains(.flag("-sanitize=undefined")))

      let linkJob = plannedJobs[3]
      let linkCmd = linkJob.commandLine
      XCTAssertTrue(linkCmd.contains(.flag("-fsanitize=address,undefined")))
    }

    do {
      // linux scudo hardened allocator
      var driver = try Driver(
        args: commonArgs + [
          "-target", "x86_64-unknown-linux",
          "-sanitize=scudo"
        ]
      )
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 4)

      let compileJob = plannedJobs[0]
      let compileCmd = compileJob.commandLine
      XCTAssertTrue(compileCmd.contains(.flag("-sanitize=scudo")))

      let linkJob = plannedJobs[3]
      let linkCmd = linkJob.commandLine
      XCTAssertTrue(linkCmd.contains(.flag("-fsanitize=scudo")))
    }
    #endif
  #endif

  // FIXME: This test will fail when not run on Android, because the driver uses
  //        the existence of the runtime support libraries to determine if
  //        a sanitizer is supported. Until we allow cross-compiling with
  //        sanitizers, this test is disabled outside Android.
  #if os(Android)
    do {
      var driver = try Driver(
        args: commonArgs + [
          "-target", "aarch64-unknown-linux-android", "-sanitize=address"
        ]
      )
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 4)

      let compileJob = plannedJobs[0]
      let compileCmd = compileJob.commandLine
      XCTAssertTrue(compileCmd.contains(.flag("-sanitize=address")))

      let linkJob = plannedJobs[3]
      let linkCmd = linkJob.commandLine
      XCTAssertTrue(linkCmd.contains(.flag("-fsanitize=address")))
    }
  #endif
  }

  func testSanitizerCoverageArgs() throws {
    try assertDriverDiagnostics(args: ["swiftc", "foo.swift", "-sanitize-coverage=func,trace-cmp"]) {
      $1.expect(.error("option '-sanitize-coverage=' requires a sanitizer to be enabled. Use -sanitize= to enable a sanitizer"))
    }

#if os(Windows)
    throw XCTSkip("tsan is not yet available on Windows")
#else
    try assertDriverDiagnostics(args: ["swiftc", "foo.swift", "-sanitize=thread", "-sanitize-coverage=bar"]) {
      $1.expect(.error("option '-sanitize-coverage=' is missing a required argument (\"func\", \"bb\", \"edge\")"))
      $1.expect(.error("unsupported argument 'bar' to option '-sanitize-coverage='"))
    }

    try assertDriverDiagnostics(args: ["swiftc", "foo.swift", "-sanitize=thread", "-sanitize-coverage=func,baz"]) {
      $1.expect(.error("unsupported argument 'baz' to option '-sanitize-coverage='"))
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-sanitize=thread", "-sanitize-coverage=edge,indirect-calls,trace-bb,trace-cmp,8bit-counters,pc-table,inline-8bit-counters")
#endif
  }

  func testSanitizerAddressUseOdrIndicator() throws {
    do {
      var driver = try Driver(args: ["swiftc", "-sanitize=address", "-sanitize-address-use-odr-indicator", "Test.swift"])

      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(plannedJobs.count, 2)
      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-sanitize=address")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-sanitize-address-use-odr-indicator")))
    }

    do {
      try assertDriverDiagnostics(args: ["swiftc", "-sanitize=thread", "-sanitize-address-use-odr-indicator", "Test.swift"]) {
        $1.expect(.warning("option '-sanitize-address-use-odr-indicator' has no effect when 'address' sanitizer is disabled. Use -sanitize=address to enable the sanitizer"))
#if os(Windows)
        $1.expect(.error("thread sanitizer is unavailable on target 'x86_64-unknown-windows-msvc'"))
#endif
      }
    }

    do {
      try assertDriverDiagnostics(args: ["swiftc", "-sanitize-address-use-odr-indicator", "Test.swift"]) {
        $1.expect(.warning("option '-sanitize-address-use-odr-indicator' has no effect when 'address' sanitizer is disabled. Use -sanitize=address to enable the sanitizer"))
      }
    }
  }

  func testSanitizeStableAbi() throws {
#if !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
      throw XCTSkip("-sanitize-stable-abi is only implemented on Darwin")
#else
    var driver = try Driver(args: ["swiftc", "-sanitize=address", "-sanitize-stable-abi", "Test.swift"])
    guard driver.isFrontendArgSupported(.sanitizeStableAbiEQ) else {
      return
    }

    do {
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(plannedJobs.count, 2)
      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-sanitize=address")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-sanitize-stable-abi")))

      XCTAssert(plannedJobs[1].commandLine.contains(.flag("-fsanitize=address")))
      XCTAssert(plannedJobs[1].commandLine.contains(.flag("-fsanitize-stable-abi")))
    }

    do {
      try assertDriverDiagnostics(args: ["swiftc","-sanitize-stable-abi", "Test.swift"]) {
        $1.expect(.warning("option '-sanitize-stable-abi' has no effect when 'address' sanitizer is disabled. Use -sanitize=address to enable the sanitizer"))
      }
    }
#endif
  }

  func testADDITIONAL_SWIFT_DRIVER_FLAGS() throws {
    var env = ProcessEnv.vars
    env["ADDITIONAL_SWIFT_DRIVER_FLAGS"] = "-Xfrontend -unknown1 -Xfrontend -unknown2"
    var driver = try Driver(args: ["swiftc", "foo.swift", "-module-name", "Test"], env: env)
    let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
    XCTAssertEqual(plannedJobs.count, 2)
    XCTAssertTrue(plannedJobs[0].commandLine.contains(.flag("-unknown1")))
    XCTAssertTrue(plannedJobs[0].commandLine.contains(.flag("-unknown2")))
    XCTAssertTrue(plannedJobs[1].kind == .link)
  }

  func testBatchModeCompiles() throws {
    do {
      var driver1 = try Driver(args: ["swiftc", "foo1.swift", "bar1.swift", "foo2.swift", "bar2.swift", "foo3.swift", "bar3.swift", "foo4.swift", "bar4.swift", "foo5.swift", "bar5.swift", "wibble.swift", "-module-name", "Test", "-enable-batch-mode", "-driver-batch-count", "3"])
      let plannedJobs = try driver1.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(plannedJobs.count, 4)
      XCTAssertEqual(plannedJobs[0].outputs.count, 4)
      XCTAssertTrue(matchTemporary(plannedJobs[0].outputs.first!.file, "foo1.o"))
      XCTAssertEqual(plannedJobs[1].outputs.count, 4)
      XCTAssertTrue(matchTemporary(plannedJobs[1].outputs.first!.file, "foo3.o"))
      XCTAssertEqual(plannedJobs[2].outputs.count, 3)
      XCTAssertTrue(matchTemporary(plannedJobs[2].outputs.first!.file, "foo5.o"))
      XCTAssertTrue(plannedJobs[3].tool.name.contains("clang"))
      XCTAssertEqual(plannedJobs[3].outputs.count, 1)
      XCTAssertEqual(plannedJobs[3].outputs.first!.file, try toPath(executableName("Test")))
    }

    // Test 1 partition results in 1 job
    do {
      var driver = try Driver(args: ["swiftc", "-toolchain-stdlib-rpath", "-module-cache-path", "/tmp/clang-module-cache", "-swift-version", "4", "-Xfrontend", "-ignore-module-source-info", "-module-name", "batch", "-enable-batch-mode", "-j", "1", "-c", "main.swift", "lib.swift"])
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(plannedJobs.count, 1)
      var count = 0
      for arg in plannedJobs[0].commandLine where arg == .flag("-primary-file") {
        count += 1
      }
      XCTAssertEqual(count, 2)
    }
  }

  func testPrivateInterfacePathImplicit() throws {
    var driver1 = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-module-name",
                                   "foo", "-emit-module-interface",
                                   "-enable-library-evolution"])

    let plannedJobs = try driver1.planBuild()
    XCTAssertEqual(plannedJobs.count, 3)

    let emitInterfaceJob = try plannedJobs.findJob(.emitModule)
    XCTAssertTrue(emitInterfaceJob.commandLine.contains(.flag("-emit-module-interface-path")))
    XCTAssertTrue(emitInterfaceJob.commandLine.contains(.flag("-emit-private-module-interface-path")))
  }

  func testPackageInterfacePathImplicit() throws {
    let envVars = ProcessEnv.vars

    // A .package.swiftinterface should only be generated if package-name is passed.
    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-module-name", "foo",
                                     "-package-name", "mypkg", "-library-level", "api",
                                     "-emit-module-interface", "-enable-library-evolution"], env: envVars)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)
      let emitInterfaceJob = plannedJobs[0]
      XCTAssertTrue(emitInterfaceJob.commandLine.contains(.flag("-emit-module-interface-path")))
      XCTAssertTrue(emitInterfaceJob.commandLine.contains(.flag("-emit-private-module-interface-path")))
      XCTAssertTrue(emitInterfaceJob.commandLine.contains(.flag("-emit-package-module-interface-path")))
    }

    // package-name is not passed, so package interface should not be generated.
    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-module-name", "foo", "-library-level", "api",
                                     "-emit-module-interface", "-enable-library-evolution"], env: envVars)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)
      let emitInterfaceJob = plannedJobs[0]
      XCTAssertTrue(emitInterfaceJob.commandLine.contains(.flag("-emit-module-interface-path")))
      XCTAssertTrue(emitInterfaceJob.commandLine.contains(.flag("-emit-private-module-interface-path")))
      XCTAssertFalse(emitInterfaceJob.commandLine.contains(.flag("-emit-package-module-interface-path")))
    }

    // package-name is not passed, so specifying emit-package-module-interface-path should be a no-op.
    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-module-name", "foo",
                                     "-emit-module-interface", "-library-level", "api",
                                     "-emit-package-module-interface-path", "foo.package.swiftinterface",
                                     "-enable-library-evolution"], env: envVars)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)
      let emitInterfaceJob = plannedJobs[0]
      XCTAssertTrue(emitInterfaceJob.commandLine.contains(.flag("-emit-module-interface-path")))
      XCTAssertTrue(emitInterfaceJob.commandLine.contains(.flag("-emit-private-module-interface-path")))
      XCTAssertFalse(emitInterfaceJob.commandLine.contains(.flag("-emit-package-module-interface-path")))
    }
  }

  func testSingleThreadedWholeModuleOptimizationCompiles() throws {
    var envVars = ProcessEnv.vars
    envVars["SWIFT_DRIVER_LD_EXEC"] = ld.nativePathString(escaped: false)
    var driver1 = try Driver(args: ["swiftc", "-whole-module-optimization", "foo.swift", "bar.swift", "-emit-library", "-emit-module", "-module-name", "Test", "-emit-module-interface", "-emit-objc-header-path", "Test-Swift.h", "-emit-private-module-interface-path", "Test.private.swiftinterface", "-emit-tbd", "-o", "libTest"],
                             env: envVars)
    let plannedJobs = try driver1.planBuild().removingAutolinkExtractJobs()
    XCTAssertEqual(plannedJobs.count, 3)
    XCTAssertEqual(Set(plannedJobs.map { $0.kind }), Set([.compile, .emitModule, .link]))

    XCTAssertEqual(plannedJobs[0].kind, .compile)
    XCTAssertEqual(plannedJobs[0].outputs.count, 1)
    XCTAssertTrue(matchTemporary(plannedJobs[0].outputs[0].file, "Test.o"))
    XCTAssert(!plannedJobs[0].commandLine.contains(.flag("-primary-file")))

    let emitModuleJob = try plannedJobs.findJob(.emitModule)
    XCTAssertEqual(emitModuleJob.outputs.count, driver1.targetTriple.isDarwin ? 8 : 7)
    XCTAssertEqual(emitModuleJob.outputs[0].file, try toPath("Test.swiftmodule"))
    XCTAssertEqual(emitModuleJob.outputs[1].file, try toPath("Test.swiftdoc"))
    XCTAssertEqual(emitModuleJob.outputs[2].file, try toPath("Test.swiftsourceinfo"))
    XCTAssertEqual(emitModuleJob.outputs[3].file, try toPath("Test.swiftinterface"))
    XCTAssertEqual(emitModuleJob.outputs[4].file, try toPath("Test.private.swiftinterface"))
    XCTAssertEqual(emitModuleJob.outputs[5].file, try toPath("Test-Swift.h"))
    XCTAssertEqual(emitModuleJob.outputs[6].file, try toPath("Test.tbd"))
    if driver1.targetTriple.isDarwin {
        XCTAssertEqual(emitModuleJob.outputs[7].file, try toPath("Test.abi.json"))
    }
    XCTAssert(!emitModuleJob.commandLine.contains(.flag("-primary-file")))
    XCTAssert(emitModuleJob.commandLine.contains(.flag("-emit-module-interface-path")))
    XCTAssert(emitModuleJob.commandLine.contains(.flag("-emit-private-module-interface-path")))
  }


  func testIndexFileEntryInSupplementaryFileOutputMap() throws {
    var driver1 = try Driver(args: [
      "swiftc", "foo1.swift", "foo2.swift", "foo3.swift", "foo4.swift", "foo5.swift",
      "-index-file", "-index-file-path", "foo5.swift", "-o", "/tmp/t.o",
      "-index-store-path", "/tmp/idx", "-working-directory", "/tmp"
    ])
    let plannedJobs = try driver1.planBuild().removingAutolinkExtractJobs()
    XCTAssertEqual(plannedJobs.count, 1)
    let map = try XCTUnwrap(plannedJobs[0].commandLine.supplementaryOutputFilemap)
    // This is to match the legacy driver behavior
    // Make sure the supplementary output map has an entry for the Swift file
    // under indexing and its indexData entry is the primary output file
    let entry = map.entries[VirtualPath.absolute(try AbsolutePath(validating: "/tmp/foo5.swift")).intern()]!
    XCTAssert(VirtualPath.lookup(entry[.indexData]!) == .absolute(try .init(validating: "/tmp/t.o")))
  }

  func testMultiThreadedWholeModuleOptimizationCompiles() throws {
    do {
      var driver1 = try Driver(args: [
        "swiftc", "-whole-module-optimization", "foo.swift", "bar.swift", "wibble.swift",
        "-module-name", "Test", "-num-threads", "4"
      ])
      let plannedJobs = try driver1.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(plannedJobs.count, 2)
      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertEqual(plannedJobs[0].outputs.count, 3)
      XCTAssertTrue(matchTemporary(plannedJobs[0].outputs[0].file, "foo.o"))
      XCTAssertTrue(matchTemporary(plannedJobs[0].outputs[1].file, "bar.o"))
      XCTAssertTrue(matchTemporary(plannedJobs[0].outputs[2].file, "wibble.o"))
      XCTAssert(!plannedJobs[0].commandLine.contains(.flag("-primary-file")))

      XCTAssertEqual(plannedJobs[1].kind, .link)
    }

    // emit-module
    do {
      var driver = try Driver(args: ["swiftc", "-module-name=ThisModule", "-wmo", "-num-threads", "4", "main.swift", "multi-threaded.swift", "-emit-module", "-o", "test.swiftmodule"])
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(plannedJobs.count, 1)
      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertEqual(plannedJobs[0].inputs.count, 2)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, try toPath("main.swift"))
      XCTAssertEqual(plannedJobs[0].inputs[1].file, try toPath("multi-threaded.swift"))
      XCTAssertEqual(plannedJobs[0].outputs.count, driver.targetTriple.isDarwin ? 4 : 3)
      XCTAssertEqual(plannedJobs[0].outputs[0].file, try toPath("test.swiftmodule"))
    }
  }

  func testEmitABIDescriptor() throws {
#if !os(macOS)
    throw XCTSkip("Skipping: ABI descriptor is only emitted on Darwin platforms.")
#endif
    do {
      var driver = try Driver(args: ["swiftc", "-module-name=ThisModule", "-wmo", "main.swift", "multi-threaded.swift", "-emit-module", "-o", "test.swiftmodule"])
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(plannedJobs.count, 1)
      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertTrue(plannedJobs[0].commandLine.contains(.flag("-emit-abi-descriptor-path")))
    }
    do {
      var driver = try Driver(args: ["swiftc", "-module-name=ThisModule", "main.swift", "multi-threaded.swift", "-emit-module", "-o", "test.swiftmodule", "-experimental-emit-module-separately"])
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertEqual(plannedJobs[0].kind, .emitModule)
      XCTAssertTrue(plannedJobs[0].commandLine.contains(.flag("-emit-abi-descriptor-path")))
    }
    do {
      var driver = try Driver(args: ["swiftc", "-module-name=ThisModule", "main.swift", "multi-threaded.swift", "-emit-module", "-o", "test.swiftmodule", "-no-emit-module-separately"])
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertEqual(plannedJobs[2].kind, .mergeModule)
      XCTAssertTrue(plannedJobs[2].commandLine.contains(.flag("-emit-abi-descriptor-path")))
    }

  }

  func testWMOWithNonSourceInput() throws {
    var driver1 = try Driver(args: [
      "swiftc", "-whole-module-optimization", "danger.o", "foo.swift", "bar.swift", "wibble.swift", "-module-name", "Test",
      "-driver-filelist-threshold=0"
    ])
    let plannedJobs = try driver1.planBuild().removingAutolinkExtractJobs()
    XCTAssertEqual(plannedJobs.count, 2)
    let compileJob = plannedJobs[0]
    XCTAssertEqual(compileJob.kind, .compile)
    let outFileMap = try XCTUnwrap(compileJob.commandLine.supplementaryOutputFilemap)
    let firstKey: String = try VirtualPath.lookup(XCTUnwrap(outFileMap.entries.keys.first)).basename
    XCTAssertEqual(firstKey, "foo.swift")
  }

  func testExplicitBuildWithJustObjectInputs() throws {
    var driver = try Driver(args: [
      "swiftc", "-explicit-module-build", "foo.o", "bar.o"
    ])
    let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
    XCTAssertEqual(plannedJobs.count, 1)
    XCTAssertEqual(plannedJobs.first?.kind, .link)
  }

  func testWMOWithNonSourceInputFirstAndModuleOutput() throws {
    var driver1 = try Driver(args: [
      "swiftc", "-wmo", "danger.o", "foo.swift", "bar.swift", "wibble.swift", "-module-name", "Test",
      "-driver-filelist-threshold=0", "-emit-module", "-emit-library", "-no-emit-module-separately-wmo"
    ])
    let plannedJobs = try driver1.planBuild().removingAutolinkExtractJobs()
    XCTAssertEqual(plannedJobs.count, 2)
    let compileJob = plannedJobs[0]
    XCTAssertEqual(compileJob.kind, .compile)
    XCTAssert(compileJob.commandLine.contains(.flag("-supplementary-output-file-map")))
    let argIdx = try XCTUnwrap(compileJob.commandLine.firstIndex(where: { $0 == .flag("-supplementary-output-file-map") }))
    let supplOutputs = compileJob.commandLine[argIdx+1]
    guard case let .path(path) = supplOutputs,
          case let .fileList(_, fileList) = path,
          case let .outputFileMap(outFileMap) = fileList else {
      throw StringError("Unexpected argument for output file map")
    }
    let firstKeyHandle = try XCTUnwrap(outFileMap.entries.keys.first)
    let firstKey = VirtualPath.lookup(firstKeyHandle).basename
    XCTAssertEqual(firstKey, "foo.swift")
    let firstKeyOutputs = try XCTUnwrap(outFileMap.entries[firstKeyHandle])
    XCTAssertTrue(firstKeyOutputs.keys.contains(where: { $0 == .swiftModule }))
  }

  func testLinkFilelistWithDebugInfo() throws {
    func getFileListElements(for filelistOpt: String, job: Job) -> [VirtualPath] {
        guard let optIdx = job.commandLine.firstIndex(of: .flag(filelistOpt)) else {
            XCTFail("Argument '\(filelistOpt)' not in job command line")
            return []
        }
        let value = job.commandLine[job.commandLine.index(after: optIdx)]
        guard case let .path(.fileList(_, valueFileList)) = value else {
            XCTFail("Argument wasn't a filelist")
            return []
        }
        guard case let .list(inputs) = valueFileList else {
            XCTFail("FileList wasn't a List")
            return []
        }
        return inputs
    }

    var driver = try Driver(args: [
        "swiftc", "-g", "/tmp/hello.swift", "-module-name", "Hello",
        "-emit-library", "-driver-filelist-threshold=0"
    ])

    var jobs = try driver.planBuild()
    XCTAssertEqual(jobs.count, 4)
    XCTAssertEqual(getFileListElements(for: "-filelist", job: jobs[2]),
        [.temporary(try .init(validating: "hello-1.o"))])
  }

  func testDashDashPassingDownInput() throws {
    do {
      var driver = try Driver(args: ["swiftc", "-module-name=ThisModule", "-wmo", "-num-threads", "4", "-emit-module", "-o", "test.swiftmodule", "--", "main.swift", "multi-threaded.swift"])
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertFalse(driver.diagnosticEngine.hasErrors)
      XCTAssertEqual(plannedJobs.count, 1)
      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertEqual(plannedJobs[0].inputs.count, 2)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, try toPath("main.swift"))
      XCTAssertEqual(plannedJobs[0].inputs[1].file, try toPath("multi-threaded.swift"))
      XCTAssertEqual(plannedJobs[0].outputs.count, driver.targetTriple.isDarwin ? 4 : 3)
      XCTAssertEqual(plannedJobs[0].outputs[0].file, try toPath("test.swiftmodule"))
    }
  }

  func testDashDashImmediateInput() throws {
    do {
      var driver = try Driver(args: ["swift", "--", "main.swift"])
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertFalse(driver.diagnosticEngine.hasErrors)
      XCTAssertEqual(plannedJobs.count, 1)
      XCTAssertEqual(plannedJobs[0].kind, .interpret)
      XCTAssertEqual(plannedJobs[0].inputs.count, 1)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, try toPath("main.swift"))
    }
  }

  func testWholeModuleOptimizationOutputFileMap() throws {
    let contents = ByteString(
      """
      {
        "": {
          "swiftinterface": "/tmp/salty/Test.swiftinterface"
        }
      }
      """.utf8
    )

    try withTemporaryFile { file in
      try assertNoDiagnostics { diags in
        try localFileSystem.writeFileContents(file.path, bytes: contents)
        var driver1 = try Driver(args: [
          "swiftc", "-whole-module-optimization", "foo.swift", "bar.swift", "wibble.swift", "-module-name", "Test",
          "-num-threads", "4", "-output-file-map", file.path.pathString, "-emit-module-interface"
        ])
        let plannedJobs = try driver1.planBuild().removingAutolinkExtractJobs()
        XCTAssertEqual(plannedJobs.count, 3)
        XCTAssertEqual(Set(plannedJobs.map { $0.kind }), Set([.compile, .emitModule, .link]))

        XCTAssertEqual(plannedJobs[0].kind, .compile)
        XCTAssertEqual(plannedJobs[0].outputs.count, 3)
        XCTAssertTrue(matchTemporary(plannedJobs[0].outputs[0].file, "foo.o"))
        XCTAssertTrue(matchTemporary(plannedJobs[0].outputs[1].file, "bar.o"))
        XCTAssertTrue(matchTemporary(plannedJobs[0].outputs[2].file, "wibble.o"))
        XCTAssert(!plannedJobs[0].commandLine.contains(.flag("-primary-file")))

        let emitModuleJob = plannedJobs.first(where: {$0.kind == .emitModule})!
        XCTAssertEqual(emitModuleJob.outputs[3].file, VirtualPath.absolute(try .init(validating: "/tmp/salty/Test.swiftinterface")))
        XCTAssert(!emitModuleJob.commandLine.contains(.flag("-primary-file")))
        XCTAssertEqual(plannedJobs[2].kind, .link)
      }
    }
  }

  func testWMOWithJustObjectInputs() throws {
    var driver = try Driver(args: [
      "swiftc", "-wmo", "foo.o", "bar.o"
    ])
    let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
    XCTAssertEqual(plannedJobs.count, 1)
    XCTAssertEqual(plannedJobs.first?.kind, .link)
  }

  func testModuleAliasingWithImplicitBuild() throws {
    var driver = try Driver(args: [
      "swiftc", "foo.swift", "-module-name", "Foo", "-module-alias", "Car=Bar",
      "-emit-module", "-emit-module-path", "/tmp/dir/Foo.swiftmodule",
    ])

    let plannedJobs = try driver.planBuild()

    let moduleJob = try plannedJobs.findJob(.emitModule)
    XCTAssertTrue(moduleJob.commandLine.contains("-module-alias"))
    XCTAssertTrue(moduleJob.commandLine.contains("Car=Bar"))
    XCTAssertEqual(moduleJob.outputs[0].file, .absolute(try .init(validating: "/tmp/dir/Foo.swiftmodule")))
    XCTAssertEqual(driver.moduleOutputInfo.name, "Foo")
    XCTAssertNotNil(driver.moduleOutputInfo.aliases)
    XCTAssertEqual(driver.moduleOutputInfo.aliases!.count, 1)
    XCTAssertEqual(driver.moduleOutputInfo.aliases!["Car"], "Bar")
  }

  func testInvalidModuleAliasing() throws {
    try assertDriverDiagnostics(
      args: ["swiftc", "foo.swift", "-module-name", "Foo", "-module-alias", "CarBar", "-emit-module", "-emit-module-path", "/tmp/dir/Foo.swiftmodule"]
    ) {
      $1.expect(.error("invalid format \"CarBar\"; use the format '-module-alias alias_name=underlying_name'"))
    }

    try assertDriverDiagnostics(
      args: ["swiftc", "foo.swift", "-module-name", "Foo", "-module-alias", "Foo=Bar", "-emit-module", "-emit-module-path", "/tmp/dir/Foo.swiftmodule"]
    ) {
      $1.expect(.error("module alias \"Foo\" should be different from the module name \"Foo\""))
    }

    try assertDriverDiagnostics(
      args: ["swiftc", "foo.swift", "-module-name", "Foo", "-module-alias", "C-ar=Bar", "-emit-module", "-emit-module-path", "/tmp/dir/Foo.swiftmodule"]
    ) {
      $1.expect(.error("module name \"C-ar\" is not a valid identifier"))
    }

    try assertDriverDiagnostics(
      args: ["swiftc", "foo.swift", "-module-name", "Foo", "-module-alias", "Car=Bar", "-module-alias", "Train=Car", "-emit-module", "-emit-module-path", "/tmp/dir/Foo.swiftmodule"]
    ) {
      $1.expect(.error("the name \"Car\" is already used for a module alias or an underlying name"))
    }

    try assertDriverDiagnostics(
      args: ["swiftc", "foo.swift", "-module-name", "Foo", "-module-alias", "Car=Bar", "-module-alias", "Car=Bus", "-emit-module", "-emit-module-path", "/tmp/dir/Foo.swiftmodule"]
    ) {
      $1.expect(.error("the name \"Car\" is already used for a module alias or an underlying name"))
    }
  }

  func testWholeModuleOptimizationUsingSupplementaryOutputFileMap() throws {
    var driver1 = try Driver(args: [
      "swiftc", "-whole-module-optimization", "foo.swift", "bar.swift", "wibble.swift", "-module-name", "Test",
      "-emit-module-interface", "-driver-filelist-threshold=0"
    ])
    let plannedJobs = try driver1.planBuild().removingAutolinkExtractJobs()
    XCTAssertEqual(plannedJobs.count, 3)
    XCTAssertEqual(plannedJobs[0].kind, .compile)
    XCTAssert(plannedJobs[0].commandLine.contains(.flag("-supplementary-output-file-map")))
  }

  func testOptimizationRecordFileInSupplementaryOutputFileMap() throws {
    func checkSupplementaryOutputFileMap(format: String, _ fileType: FileType) throws {
      var driver1 = try Driver(args: [
        "swiftc", "-whole-module-optimization", "foo.swift", "bar.swift", "wibble.swift", "-module-name", "Test",
        "-save-optimization-record=\(format)", "-driver-filelist-threshold=0"
      ])
      let plannedJobs = try driver1.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(plannedJobs.count, 2)
      XCTAssertEqual(plannedJobs[0].kind, .compile)
      print(plannedJobs[0].commandLine.joinedUnresolvedArguments)
      let outFileMap = try XCTUnwrap(plannedJobs[0].commandLine.supplementaryOutputFilemap)
      XCTAssertEqual(outFileMap.entries.values.first?.keys.first, fileType)
    }

    try checkSupplementaryOutputFileMap(format: "yaml", .yamlOptimizationRecord)
    try checkSupplementaryOutputFileMap(format: "bitstream", .bitstreamOptimizationRecord)
  }

  func testUpdateCode() throws {
    do {
      var driver = try Driver(args: [
        "swiftc", "-update-code", "foo.swift", "bar.swift"
      ])
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertEqual(plannedJobs.map(\.kind), [.compile, .compile, .link])
      XCTAssertTrue(commandContainsFlagTemporaryPathSequence(plannedJobs[0].commandLine,
                                                             flag: "-emit-remap-file-path",
                                                             filename: "foo.remap"))
      XCTAssertTrue(commandContainsFlagTemporaryPathSequence(plannedJobs[1].commandLine,
                                                             flag: "-emit-remap-file-path",
                                                             filename: "bar.remap"))
    }

    try assertDriverDiagnostics(
      args: ["swiftc", "-update-code", "foo.swift", "bar.swift", "-enable-batch-mode", "-driver-batch-count", "1"]
    ) {
      _ = try? $0.planBuild()
      $1.expect(.error("using '-update-code' in batch compilation mode is not supported"))
    }

    try assertDriverDiagnostics(
      args: ["swiftc", "-update-code", "foo.swift", "bar.swift", "-wmo"]
    ) {
      _ = try? $0.planBuild()
      $1.expect(.error("using '-update-code' in whole module optimization mode is not supported"))
    }

    do {
      var driver = try Driver(args: [
        "swiftc", "-update-code", "foo.swift", "-migrate-keep-objc-visibility"
      ])
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(plannedJobs.count, 2)
      XCTAssertEqual(plannedJobs.map(\.kind), [.compile, .link])
      XCTAssertTrue(commandContainsFlagTemporaryPathSequence(plannedJobs[0].commandLine,
                                                             flag: "-emit-remap-file-path",
                                                             filename: "foo.remap"))
      XCTAssertTrue(plannedJobs[0].commandLine.contains("-migrate-keep-objc-visibility"))
    }
  }

  func testMergeModulesOnly() throws {
    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module", "-disable-bridging-pch", "-import-objc-header", "TestInputHeader.h", "-emit-dependencies", "-emit-module-source-info-path", "/foo/bar/Test.swiftsourceinfo", "-no-emit-module-separately"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertEqual(Set(plannedJobs.map { $0.kind }), Set([.compile, .mergeModule]))
      XCTAssertEqual(plannedJobs[0].outputs.count, 4)

      XCTAssertTrue(matchTemporary(plannedJobs[0].outputs[0].file, "foo.swiftmodule"))
      XCTAssertTrue(matchTemporary(plannedJobs[0].outputs[1].file, "foo.swiftdoc"))
      XCTAssertTrue(matchTemporary(plannedJobs[0].outputs[2].file, "foo.swiftsourceinfo"))
      XCTAssertTrue(matchTemporary(plannedJobs[0].outputs[3].file, "foo.d"))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-import-objc-header")))

      XCTAssertEqual(plannedJobs[1].outputs.count, 4)
      XCTAssertTrue(matchTemporary(plannedJobs[1].outputs[0].file, "bar.swiftmodule"))
      XCTAssertTrue(matchTemporary(plannedJobs[1].outputs[1].file, "bar.swiftdoc"))
      XCTAssertTrue(matchTemporary(plannedJobs[1].outputs[2].file, "bar.swiftsourceinfo"))
      XCTAssertTrue(matchTemporary(plannedJobs[1].outputs[3].file, "bar.d"))
      XCTAssert(plannedJobs[1].commandLine.contains(.flag("-import-objc-header")))

      XCTAssertTrue(plannedJobs[2].tool.name.contains("swift"))
      XCTAssertEqual(plannedJobs[2].outputs.count, driver.targetTriple.isDarwin ? 4 : 3)
      XCTAssertEqual(plannedJobs[2].outputs[0].file, try toPath("Test.swiftmodule"))
      XCTAssertEqual(plannedJobs[2].outputs[1].file, try toPath("Test.swiftdoc"))
      XCTAssertEqual(plannedJobs[2].outputs[2].file, .absolute(try .init(validating: "/foo/bar/Test.swiftsourceinfo")))
      if driver.targetTriple.isDarwin {
          XCTAssertEqual(plannedJobs[2].outputs[3].file, try toPath("Test.abi.json"))
      }
      XCTAssert(plannedJobs[2].commandLine.contains(.flag("-import-objc-header")))
    }

    do {
      let root = localFileSystem.currentWorkingDirectory!.appending(components: "foo", "bar")

      var driver = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module-path", rebase("Test.swiftmodule", at: root), "-no-emit-module-separately"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertTrue(plannedJobs[2].tool.name.contains("swift"))
      XCTAssertEqual(plannedJobs[2].outputs.count, driver.targetTriple.isDarwin ? 4 : 3)
      XCTAssertEqual(plannedJobs[2].outputs[0].file, .absolute(try .init(validating: rebase("Test.swiftmodule", at: root))))
      XCTAssertEqual(plannedJobs[2].outputs[1].file, .absolute(try .init(validating: rebase("Test.swiftdoc", at: root))))
      XCTAssertEqual(plannedJobs[2].outputs[2].file, .absolute(try .init(validating: rebase("Test.swiftsourceinfo", at: root))))
      if driver.targetTriple.isDarwin {
          XCTAssertEqual(plannedJobs[2].outputs[3].file, .absolute(try .init(validating: rebase("Test.abi.json", at: root))))
      }
    }

    do {
      // Make sure the swiftdoc path is correct for a relative module
      var driver = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module-path", "Test.swiftmodule", "-no-emit-module-separately"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertTrue(plannedJobs[2].tool.name.contains("swift"))
      XCTAssertEqual(plannedJobs[2].outputs.count, driver.targetTriple.isDarwin ? 4 : 3)
      XCTAssertEqual(plannedJobs[2].outputs[0].file, try toPath("Test.swiftmodule"))
      XCTAssertEqual(plannedJobs[2].outputs[1].file, try toPath("Test.swiftdoc"))
      XCTAssertEqual(plannedJobs[2].outputs[2].file, try toPath("Test.swiftsourceinfo"))
      if driver.targetTriple.isDarwin {
          XCTAssertEqual(plannedJobs[2].outputs[3].file, try toPath("Test.abi.json"))
      }
    }

    do {
      // Make sure the swiftdoc path is correct for an inferred module
      var driver = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module", "-no-emit-module-separately"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertTrue(plannedJobs[2].tool.name.contains("swift"))
      XCTAssertEqual(plannedJobs[2].outputs.count, driver.targetTriple.isDarwin ? 4 : 3)
      XCTAssertEqual(plannedJobs[2].outputs[0].file, try toPath("Test.swiftmodule"))
      XCTAssertEqual(plannedJobs[2].outputs[1].file, try toPath("Test.swiftdoc"))
      XCTAssertEqual(plannedJobs[2].outputs[2].file, try toPath("Test.swiftsourceinfo"))
      if driver.targetTriple.isDarwin {
          XCTAssertEqual(plannedJobs[2].outputs[3].file, try toPath("Test.abi.json"))
      }
    }

    do {
      // -o specified
      var driver = try Driver(args: ["swiftc", "-emit-module", "-o", "/tmp/test.swiftmodule", "input.swift", "-no-emit-module-separately"])
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 2)
      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertTrue(matchTemporary(plannedJobs[0].outputs[0].file, "input.swiftmodule"))
      XCTAssertEqual(plannedJobs[1].kind, .mergeModule)
      XCTAssertTrue(matchTemporary(plannedJobs[1].inputs[0].file, "input.swiftmodule"))
      XCTAssertEqual(plannedJobs[1].outputs[0].file, .absolute(try .init(validating: "/tmp/test.swiftmodule")))
    }
  }

  func testEmitModuleSeparately() throws {
    var envVars = ProcessEnv.vars
    envVars["SWIFT_DRIVER_LD_EXEC"] = ld.nativePathString(escaped: false)

    do {
      let root = localFileSystem.currentWorkingDirectory!.appending(components: "foo", "bar")

      var driver = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module-path", rebase("Test.swiftmodule", at: root), "-emit-symbol-graph", "-emit-symbol-graph-dir", "/foo/bar/", "-experimental-emit-module-separately", "-emit-library"],
                              env: envVars)
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(plannedJobs.count, 4)
      XCTAssertEqual(Set(plannedJobs.map { $0.kind }), Set([.compile, .emitModule, .link]))
      XCTAssertTrue(plannedJobs[0].tool.name.contains("swift"))
      XCTAssertTrue(plannedJobs[0].commandLine.contains(.flag("-parse-as-library")))
      XCTAssertEqual(plannedJobs[0].outputs.count, driver.targetTriple.isDarwin ? 4 : 3)
      XCTAssertEqual(plannedJobs[0].outputs[0].file, .absolute(try .init(validating: rebase("Test.swiftmodule", at: root))))
      XCTAssertEqual(plannedJobs[0].outputs[1].file, .absolute(try .init(validating: rebase("Test.swiftdoc", at: root))))
      XCTAssertEqual(plannedJobs[0].outputs[2].file, .absolute(try .init(validating: rebase("Test.swiftsourceinfo", at: root))))
      if driver.targetTriple.isDarwin {
          XCTAssertEqual(plannedJobs[0].outputs[3].file, .absolute(try .init(validating: rebase("Test.abi.json", at: root))))
      }

      // We don't know the output file of the symbol graph, just make sure the flag is passed along.
      XCTAssertTrue(plannedJobs[0].commandLine.contains(.flag("-emit-symbol-graph-dir")))
    }

    do {
      let root = localFileSystem.currentWorkingDirectory!.appending(components: "foo", "bar")

      // We don't expect partial jobs when asking only for the swiftmodule with
      // -experimental-emit-module-separately.
      var driver = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module-path", rebase("Test.swiftmodule", at: root), "-experimental-emit-module-separately"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertEqual(Set(plannedJobs.map { $0.kind }), Set([.emitModule, .compile]))
      XCTAssertTrue(plannedJobs[0].tool.name.contains("swift"))
      XCTAssertEqual(plannedJobs[0].outputs.count, driver.targetTriple.isDarwin ? 4 : 3)
      XCTAssertEqual(plannedJobs[0].outputs[0].file, .absolute(try .init(validating: rebase("Test.swiftmodule", at: root))))
      XCTAssertEqual(plannedJobs[0].outputs[1].file, .absolute(try .init(validating: rebase("Test.swiftdoc", at: root))))
      XCTAssertEqual(plannedJobs[0].outputs[2].file, .absolute(try .init(validating: rebase("Test.swiftsourceinfo", at: root))))
      if driver.targetTriple.isDarwin {
          XCTAssertEqual(plannedJobs[0].outputs[3].file, .absolute(try .init(validating: rebase("Test.abi.json", at: root))))
      }
    }

    do {
      // Specifying -no-emit-module-separately uses a mergeModule job.
      var driver = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module-path", "/foo/bar/Test.swiftmodule", "-experimental-emit-module-separately", "-no-emit-module-separately" ])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertEqual(Set(plannedJobs.map { $0.kind }), Set([.compile, .mergeModule]))
    }

    do {
      // Calls using the driver to link a library shouldn't trigger an emit-module job, like in LLDB tests.
      var driver = try Driver(args: ["swiftc", "-emit-library", "foo.swiftmodule", "foo.o", "-emit-module-path", "foo.swiftmodule", "-experimental-emit-module-separately", "-target", "x86_64-apple-macosx10.15", "-module-name", "Test"],
                              env: envVars)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      XCTAssertEqual(Set(plannedJobs.map { $0.kind }), Set([.link]))
    }

    do {
      // Use emit-module to build sil files.
      var driver = try Driver(args: ["swiftc", "foo.sil", "bar.sil", "-module-name", "Test", "-emit-module-path", "/foo/bar/Test.swiftmodule", "-experimental-emit-module-separately", "-emit-library", "-target", "x86_64-apple-macosx10.15"],
                              env: envVars)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 4)
      XCTAssertEqual(Set(plannedJobs.map { $0.kind }), Set([.compile, .emitModule, .link]))
    }

    do {
      // Schedule an emit-module separately job even if there are non-compilable inputs.
      var driver = try Driver(args: ["swiftc", "foo.swift", "bar.dylib", "-emit-library", "foo.dylib", "-emit-module-path", "foo.swiftmodule"],
                              env: envVars)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertEqual(Set(plannedJobs.map { $0.kind }), Set([.compile, .emitModule, .link]))

      let emitJob = try plannedJobs.findJob(.emitModule)
      XCTAssertTrue(emitJob.commandLine.contains(try toPathOption("foo.swift")))
      XCTAssertFalse(emitJob.commandLine.contains(try toPathOption("bar.dylib")))

      let linkJob = try plannedJobs.findJob(.link)
      XCTAssertTrue(linkJob.commandLine.contains(try toPathOption("bar.dylib")))
    }
  }

  func testEmitModuleSeparatelyWMO() throws {
    var envVars = ProcessEnv.vars
    envVars["SWIFT_DRIVER_LD_EXEC"] = ld.nativePathString(escaped: false)
    let root = localFileSystem.currentWorkingDirectory!.appending(components: "foo", "bar")

    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module-path", rebase("Test.swiftmodule", at: root), "-emit-symbol-graph", "-emit-symbol-graph-dir", root.pathString, "-emit-library", "-target", "x86_64-apple-macosx10.15", "-wmo", "-emit-module-separately-wmo"],
                               env: envVars)

      let abiFileCount = (driver.isFeatureSupported(.emit_abi_descriptor) && driver.targetTriple.isDarwin) ? 1 : 0
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertEqual(Set(plannedJobs.map { $0.kind }), Set([.compile, .emitModule, .link]))

      // The compile job only produces the object file.
      let compileJob = try plannedJobs.findJob(.compile)
      XCTAssertTrue(compileJob.tool.name.contains("swift"))
      XCTAssertTrue(compileJob.commandLine.contains(.flag("-parse-as-library")))
      XCTAssertEqual(compileJob.outputs.count, 1)
      XCTAssertEqual(1, compileJob.outputs.filter({$0.type == .object}).count)

      // The emit module job produces the module files.
      let emitModuleJob = try plannedJobs.findJob(.emitModule)
      XCTAssertTrue(emitModuleJob.tool.name.contains("swift"))
      XCTAssertEqual(emitModuleJob.outputs.count, 3 + abiFileCount)
      XCTAssertEqual(1, try emitModuleJob.outputs.filter({$0.file == .absolute(try .init(validating: rebase("Test.swiftmodule", at: root)))}).count)
      XCTAssertEqual(1, try emitModuleJob.outputs.filter({$0.file == .absolute(try .init(validating: rebase("Test.swiftdoc", at: root)))}).count)
      XCTAssertEqual(1, try emitModuleJob.outputs.filter({$0.file == .absolute(try .init(validating: rebase("Test.swiftsourceinfo", at: root)))}).count)
      if abiFileCount == 1 {
          XCTAssertEqual(abiFileCount, try emitModuleJob.outputs.filter({$0.file == .absolute(try .init(validating: rebase("Test.abi.json", at: root)))}).count)
      }

      // We don't know the output file of the symbol graph, just make sure the flag is passed along.
      XCTAssertTrue(emitModuleJob.commandLine.contains(.flag("-emit-symbol-graph-dir")))
    }

    do {
      // Ignore the `-emit-module-separately-wmo` flag when building only the module files to avoid duplicating outputs.
      var driver = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module-path", rebase("Test.swiftmodule", at: root), "-wmo", "-emit-module-separately-wmo"])
      let abiFileCount = (driver.isFeatureSupported(.emit_abi_descriptor) && driver.targetTriple.isDarwin) ? 1 : 0
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      XCTAssertEqual(Set(plannedJobs.map { $0.kind }), Set([.compile]))

      // The compile job produces the module files.
      let emitModuleJob = plannedJobs[0]
      XCTAssertTrue(emitModuleJob.tool.name.contains("swift"))
      XCTAssertEqual(emitModuleJob.outputs.count, 3 + abiFileCount)
      XCTAssertEqual(1, try emitModuleJob.outputs.filter({$0.file == .absolute(try .init(validating: rebase("Test.swiftmodule", at: root)))}).count)
      XCTAssertEqual(1, try emitModuleJob.outputs.filter({$0.file == .absolute(try .init(validating: rebase("Test.swiftdoc", at: root)))}).count)
      XCTAssertEqual(1, try emitModuleJob.outputs.filter({$0.file == .absolute(try .init(validating: rebase("Test.swiftsourceinfo", at: root)))}).count)
      if abiFileCount == 1 {
          XCTAssertEqual(abiFileCount, try emitModuleJob.outputs.filter({$0.file == .absolute(try .init(validating: rebase("Test.abi.json", at: root)))}).count)
      }
    }

    do {
      // Specifying -no-emit-module-separately-wmo doesn't schedule the separate emit-module job.
      var driver = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module-path", rebase("Test.swiftmodule", at: root), "-emit-library", "-wmo", "-emit-module-separately-wmo", "-no-emit-module-separately-wmo" ])
      let abiFileCount = (driver.isFeatureSupported(.emit_abi_descriptor) && driver.targetTriple.isDarwin) ? 1 : 0
      let plannedJobs = try driver.planBuild()
      #if os(Linux) || os(Android)
      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertEqual(Set(plannedJobs.map { $0.kind }), Set([.compile, .link, .autolinkExtract]))
      #else
      XCTAssertEqual(plannedJobs.count, 2)
      XCTAssertEqual(Set(plannedJobs.map { $0.kind }), Set([.compile, .link]))
      #endif

      // The compile job produces both the object file and the module files.
      let compileJob = try plannedJobs.findJob(.compile)
      XCTAssertEqual(compileJob.outputs.count, 4 + abiFileCount)
      XCTAssertEqual(1, compileJob.outputs.filter({$0.type == .object}).count)
      XCTAssertEqual(1, try compileJob.outputs.filter({$0.file == .absolute(try .init(validating: rebase("Test.swiftmodule", at: root)))}).count)
      XCTAssertEqual(1, try compileJob.outputs.filter({$0.file == .absolute(try .init(validating: rebase("Test.swiftdoc", at: root)))}).count)
      XCTAssertEqual(1, try compileJob.outputs.filter({$0.file == .absolute(try .init(validating: rebase("Test.swiftsourceinfo", at: root)))}).count)
      if abiFileCount == 1 {
          XCTAssertEqual(abiFileCount, try compileJob.outputs.filter({$0.file == .absolute(try .init(validating: rebase("Test.abi.json", at: root)))}).count)
      }
    }

    do {
      // non library-evolution builds require a single job, because cross-module-optimization is enabled by default.
      var driver = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module-path", rebase("Test.swiftmodule", at: root), "-c", "-o", rebase("test.o", at: root), "-wmo", "-O" ])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      XCTAssertTrue(plannedJobs[0].commandLine.contains(.flag("-enable-default-cmo")))
    }

    do {
      // library-evolution builds can emit the module in a separate job.
      var driver = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module-path", rebase("Test.swiftmodule", at: root), "-c", "-o", rebase("test.o", at: root), "-wmo", "-O", "-enable-library-evolution" ])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 2)
      XCTAssertFalse(plannedJobs[0].commandLine.contains(.flag("-enable-default-cmo")))
      XCTAssertFalse(plannedJobs[1].commandLine.contains(.flag("-enable-default-cmo")))
    }

    do {
      // When disabling cross-module-optimization, the module can be emitted in a separate job.
      var driver = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module-path", rebase("Test.swiftmodule", at: root), "-c", "-o", rebase("test.o", at: root), "-wmo", "-O", "-disable-cmo" ])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 2)
      XCTAssertFalse(plannedJobs[0].commandLine.contains(.flag("-enable-default-cmo")))
      XCTAssertFalse(plannedJobs[1].commandLine.contains(.flag("-enable-default-cmo")))
    }

    do {
      // non optimized builds can emit the module in a separate job.
      var driver = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module-path", rebase("Test.swiftmodule", at: root), "-c", "-o", rebase("test.o", at: root), "-wmo" ])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 2)
      XCTAssertFalse(plannedJobs[0].commandLine.contains(.flag("-enable-default-cmo")))
      XCTAssertFalse(plannedJobs[1].commandLine.contains(.flag("-enable-default-cmo")))
    }

    do {
      // Don't use emit-module-separetely as a linker.
      var driver = try Driver(args: ["swiftc", "foo.sil", "bar.sil", "-module-name", "Test", "-emit-module-path", "/foo/bar/Test.swiftmodule", "-emit-library", "-target", "x86_64-apple-macosx10.15", "-wmo", "-emit-module-separately-wmo"],
                               env: envVars)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertEqual(Set(plannedJobs.map { $0.kind }), Set([.compile, .emitModule, .link]))
    }
  }

  func testModuleWrapJob() throws {
    // FIXME: These tests will fail when run on macOS, because
    // swift-autolink-extract is not present
    #if os(Linux) || os(Android)
    do {
      var driver = try Driver(args: ["swiftc", "-target", "x86_64-unknown-linux-gnu", "-g", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 5)
      XCTAssertEqual(Set(plannedJobs.map { $0.kind }), Set([.compile, .emitModule, .autolinkExtract, .moduleWrap, .link]))
      let wrapJob = try plannedJobs.findJob(.moduleWrap)
      XCTAssertEqual(wrapJob.inputs.count, 1)
      XCTAssertTrue(wrapJob.commandLine.contains(subsequence: ["-target", "x86_64-unknown-linux-gnu"]))
      let mergeJob = try plannedJobs.findJob(.emitModule)
      XCTAssertTrue(mergeJob.outputs.contains(wrapJob.inputs.first!))
      XCTAssertTrue(plannedJobs[4].inputs.contains(wrapJob.outputs.first!))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-target", "x86_64-unknown-linux-gnu", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)
      // No merge module/module wrap jobs.
      XCTAssertEqual(Set(plannedJobs.map { $0.kind }), Set([.compile, .autolinkExtract, .link]))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-target", "x86_64-unknown-linux-gnu", "-gdwarf-types", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 4)
      // Merge module, but no module wrapping.
      XCTAssertEqual(Set(plannedJobs.map { $0.kind }), Set([.compile, .emitModule, .autolinkExtract, .link]))
    }
    #endif
    // dsymutil won't be found on other platforms
    #if os(macOS)
    do {
      var driver = try Driver(args: ["swiftc", "-target", "x86_64-apple-macosx10.15", "-g", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 4)
      // No module wrapping with Mach-O.
      XCTAssertEqual(plannedJobs.map { $0.kind }, [.emitModule, .compile, .link, .generateDSYM])
    }
    #endif
  }

  func testRepl() throws {
    // Do not run this test if no LLDB is found in the toolchain.
    if try !testEnvHasLLDB() {
      throw XCTSkip()
    }

    func isExpectedLLDBREPLFlag(_ arg: Job.ArgTemplate) -> Bool {
      if case let .squashedArgumentList(option: opt, args: args) = arg {
        return opt == "--repl=" && !args.contains("-module-name")
      }
      return false
    }

    do {
      var driver = try Driver(args: ["swift"], env: envWithFakeSwiftHelp)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)

      let helpJob = plannedJobs[0]
      XCTAssertTrue(helpJob.tool.name.contains("swift-help"))
      XCTAssertTrue(helpJob.commandLine.contains(.flag("intro")))
    }

    do {
      var driver = try Driver(args: ["swift", "-repl"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      let replJob = plannedJobs.first!
      XCTAssertTrue(replJob.tool.name.contains("lldb"))
      XCTAssertTrue(replJob.requiresInPlaceExecution)
      XCTAssert(replJob.commandLine.contains(where: { isExpectedLLDBREPLFlag($0) }))
    }

    do {
      let (mode, args) = try Driver.invocationRunMode(forArgs: ["swift", "repl"])
      XCTAssertEqual(mode, .normal(isRepl: true))
      var driver = try Driver(args: args)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      let replJob = plannedJobs.first!
      XCTAssertTrue(replJob.tool.name.contains("lldb"))
      XCTAssertTrue(replJob.requiresInPlaceExecution)
      XCTAssert(replJob.commandLine.contains(where: { isExpectedLLDBREPLFlag($0) }))
    }

    do {
      XCTAssertThrowsError(try Driver(args: ["swift", "-deprecated-integrated-repl"])) {
        XCTAssertEqual($0 as? Driver.Error, Driver.Error.integratedReplRemoved)
      }
    }

    do {
      var driver = try Driver(args: ["swift", "-repl", "/foo/bar/Test.swift"])
      XCTAssertThrowsError(try driver.planBuild()) { error in
        XCTAssertEqual(error as? PlanningError, .replReceivedInput)
      }
    }

    do {
      // Linked library arguments with space
      var driver = try Driver(args: ["swift", "-repl", "-l", "somelib", "-lotherlib"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      let cmd = plannedJobs.first!.commandLine
      guard case let .squashedArgumentList(option: _, args: args) = cmd[0] else {
        XCTFail()
        return
      }
      XCTAssertTrue(args.contains(.flag("-lsomelib")))
      XCTAssertTrue(args.contains(.flag("-lotherlib")))
    }
  }

  func testInstallAPI() throws {
    let modulePath = "/tmp/FooMod.swiftmodule"
    var driver = try Driver(args: ["swiftc", "foo.swift", "-whole-module-optimization",
                                   "-module-name", "FooMod",
                                   "-emit-tbd", "-emit-tbd-path", "/tmp/FooMod.tbd",
                                   "-emit-module", "-emit-module-path", modulePath])
    let plannedJobs = try driver.planBuild()
    XCTAssertEqual(plannedJobs.count, 1)
    XCTAssertEqual(plannedJobs[0].kind, .compile)
    XCTAssertTrue(plannedJobs[0].commandLine.contains(.flag("-frontend")))
    XCTAssertTrue(plannedJobs[0].commandLine.contains(.flag("-emit-module")))
    XCTAssertTrue(plannedJobs[0].commandLine.contains(.flag("-o")))
    XCTAssertTrue(plannedJobs[0].commandLine.contains(.path(try VirtualPath(path: modulePath))))
  }

  func testEnableRegexLiteralFlag() throws {
    var driver = try Driver(args: ["swiftc", "foo.swift", "-enable-bare-slash-regex"])
    guard driver.isFrontendArgSupported(.enableBareSlashRegex) else {
      throw XCTSkip("Skipping: compiler does not support '-enable-bare-slash-regex'")
    }
    let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
    XCTAssertEqual(plannedJobs.count, 2)
    XCTAssertEqual(plannedJobs[0].kind, .compile)
    XCTAssertEqual(plannedJobs[1].kind, .link)
    XCTAssertTrue(plannedJobs[0].commandLine.contains(.flag("-frontend")))
    XCTAssertTrue(plannedJobs[0].commandLine.contains(.flag("-enable-bare-slash-regex")))
  }

  func testImmediateMode() throws {
    do {
      var driver = try Driver(args: ["swift", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      let job = plannedJobs[0]
      XCTAssertTrue(job.requiresInPlaceExecution)
      XCTAssertEqual(job.inputs.count, 1)
      XCTAssertEqual(job.inputs[0].file, try toPath("foo.swift"))
      XCTAssertEqual(job.outputs.count, 0)
      XCTAssertTrue(job.commandLine.contains(.flag("-frontend")))
      XCTAssertTrue(job.commandLine.contains(.flag("-interpret")))
      XCTAssertTrue(job.commandLine.contains(.flag("-module-name")))
      XCTAssertTrue(job.commandLine.contains(.flag("foo")))

      if driver.targetTriple.isMacOSX {
        XCTAssertTrue(job.commandLine.contains(.flag("-sdk")))
      }

      XCTAssertFalse(job.commandLine.contains(.flag("--")))

      let envVar: String
      if driver.targetTriple.isDarwin {
        envVar = "DYLD_LIBRARY_PATH"
      } else if driver.targetTriple.isWindows {
        envVar = "Path"
      } else {
        // assume Unix
        envVar = "LD_LIBRARY_PATH"
      }

      // The library search path applies to import libraries not runtime
      // libraries on Windows.  There is no way to derive the path from the
      // command on Windows.
      if !driver.targetTriple.isWindows {
        #if os(macOS)
        // On darwin, swift ships in the OS. Immediate mode should use that runtime.
        XCTAssertFalse(job.extraEnvironment.keys.contains(envVar))
        #else
        XCTAssertTrue(job.extraEnvironment.keys.contains(envVar))
        #endif
      }
    }

    do {
      var driver = try Driver(args: ["swift", "foo.swift", "-some", "args", "-for=foo"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      let job = plannedJobs[0]
      XCTAssertTrue(job.requiresInPlaceExecution)
      XCTAssertEqual(job.inputs.count, 1)
      XCTAssertEqual(job.inputs[0].file, try toPath("foo.swift"))
      XCTAssertEqual(job.outputs.count, 0)
      XCTAssertTrue(job.commandLine.contains(.flag("-frontend")))
      XCTAssertTrue(job.commandLine.contains(.flag("-interpret")))
      XCTAssertTrue(job.commandLine.contains(.flag("-module-name")))
      XCTAssertTrue(job.commandLine.contains(.flag("foo")))
      XCTAssertTrue(job.commandLine.contains(.flag("--")))
      XCTAssertTrue(job.commandLine.contains(.flag("-some")))
      XCTAssertTrue(job.commandLine.contains(.flag("args")))
      XCTAssertTrue(job.commandLine.contains(.flag("-for=foo")))
    }

    do {
      var driver = try Driver(args: ["swift", "-L/path/to/lib", "-F/path/to/framework", "-lsomelib", "-l", "otherlib", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      let job = plannedJobs[0]
      XCTAssertTrue(job.requiresInPlaceExecution)
      XCTAssertEqual(job.inputs.count, 1)
      XCTAssertEqual(job.inputs[0].file, try toPath("foo.swift"))
      XCTAssertEqual(job.outputs.count, 0)

      let envVar: String
      if driver.targetTriple.isDarwin {
        envVar = "DYLD_LIBRARY_PATH"
      } else if driver.targetTriple.isWindows {
        envVar = "Path"
      } else {
        // assume Unix
        envVar = "LD_LIBRARY_PATH"
      }

      // The library search path applies to import libraries not runtime
      // libraries on Windows.  There is no way to derive the path from the
      // command on Windows.
      if !driver.targetTriple.isWindows {
        XCTAssertTrue(job.extraEnvironment[envVar, default: ""].contains("/path/to/lib"))
        if driver.targetTriple.isDarwin {
          XCTAssertTrue(job.extraEnvironment["DYLD_FRAMEWORK_PATH", default: ""].contains("/path/to/framework"))
        }
      }

      XCTAssertTrue(job.commandLine.contains(.flag("-lsomelib")))
      XCTAssertTrue(job.commandLine.contains(.flag("-lotherlib")))
    }
  }

  func testTargetTriple() throws {
    let driver1 = try Driver(args: ["swiftc", "-c", "foo.swift", "-module-name", "Foo"])

    let expectedDefaultContents: String
    #if os(macOS)
    expectedDefaultContents = "-apple-macosx"
    #elseif os(Linux) || os(Android)
    expectedDefaultContents = "-unknown-linux"
    #elseif os(Windows)
    expectedDefaultContents = "-unknown-windows-msvc"
    #else
    expectedDefaultContents = "-"
    #endif

    XCTAssert(driver1.targetTriple.triple.contains(expectedDefaultContents),
              "Default triple \(driver1.targetTriple) contains \(expectedDefaultContents)")

    let driver2 = try Driver(args: ["swiftc", "-c", "-target", "x86_64-apple-watchos12", "foo.swift", "-module-name", "Foo"])
    XCTAssertEqual(
      driver2.targetTriple.triple, "x86_64-apple-watchos12-simulator")

    let driver3 = try Driver(args: ["swiftc", "-c", "-target", "x86_64-watchos12", "foo.swift", "-module-name", "Foo"])
    XCTAssertEqual(
      driver3.targetTriple.triple, "x86_64-unknown-watchos12-simulator")
  }

  func testTargetVariant() throws {
    var envVars = ProcessEnv.vars
    envVars["SWIFT_DRIVER_LD_EXEC"] = ld.nativePathString(escaped: false)

    do {
      var driver = try Driver(args: ["swiftc", "-c", "-target", "x86_64-apple-ios13.1-macabi", "-target-variant", "x86_64-apple-macosx10.14", "foo.swift"],
                              env: envVars)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)

      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-target")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("x86_64-apple-ios13.1-macabi")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-target-variant")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("x86_64-apple-macosx10.14")))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-emit-library", "-target", "x86_64-apple-ios13.1-macabi", "-target-variant", "x86_64-apple-macosx10.14", "-module-name", "foo", "foo.swift"],
                              env: envVars)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 2)

      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-target")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("x86_64-apple-ios13.1-macabi")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-target-variant")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("x86_64-apple-macosx10.14")))

      XCTAssertEqual(plannedJobs[1].kind, .link)
      XCTAssert(plannedJobs[1].commandLine.contains(.flag("--target=x86_64-apple-ios13.1-macabi")))
      XCTAssert(plannedJobs[1].commandLine.contains(.flag("-darwin-target-variant=x86_64-apple-macosx10.14")))
    }

    // Test -target-variant is passed to generate pch job
    do {
      var driver = try Driver(args: ["swiftc", "-target", "x86_64-apple-ios13.1-macabi", "-target-variant", "x86_64-apple-macosx10.14", "-enable-bridging-pch", "-import-objc-header", "TestInputHeader.h", "foo.swift"],
                              env: envVars)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)

      XCTAssertEqual(plannedJobs[0].kind, .generatePCH)
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-emit-pch")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-target")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("x86_64-apple-ios13.1-macabi")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-target-variant")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("x86_64-apple-macosx10.14")))

      XCTAssertEqual(plannedJobs[1].kind, .compile)
      XCTAssert(plannedJobs[1].commandLine.contains(.flag("-target")))
      XCTAssert(plannedJobs[1].commandLine.contains(.flag("x86_64-apple-ios13.1-macabi")))
      XCTAssert(plannedJobs[1].commandLine.contains(.flag("-target-variant")))
      XCTAssert(plannedJobs[1].commandLine.contains(.flag("x86_64-apple-macosx10.14")))

      XCTAssertEqual(plannedJobs[2].kind, .link)
      XCTAssert(plannedJobs[2].commandLine.contains(.flag("--target=x86_64-apple-ios13.1-macabi")))
      XCTAssert(plannedJobs[2].commandLine.contains(.flag("-darwin-target-variant=x86_64-apple-macosx10.14")))
    }
  }

  func testValidDeprecatedTargetiOS() throws {
    var driver = try Driver(args: ["swiftc", "-emit-module", "-target", "armv7-apple-ios13.0", "foo.swift"])
    let plannedJobs = try driver.planBuild()
    let emitModuleJob = try plannedJobs.findJob(.emitModule)
    XCTAssert(emitModuleJob.commandLine.contains(.flag("-target")))
    XCTAssert(emitModuleJob.commandLine.contains(.flag("armv7-apple-ios13.0")))
  }

  func testValidDeprecatedTargetWatchOS() throws {
    var driver = try Driver(args: ["swiftc", "-emit-module", "-target", "armv7k-apple-watchos10.0", "foo.swift"])
    let plannedJobs = try driver.planBuild()
    let emitModuleJob = try plannedJobs.findJob(.emitModule)
    XCTAssert(emitModuleJob.commandLine.contains(.flag("-target")))
    XCTAssert(emitModuleJob.commandLine.contains(.flag("armv7k-apple-watchos10.0")))
  }

  func testClangTargetForExplicitModule() throws {
    #if os(macOS)
    let sdkRoot = try testInputsPath.appending(component: "SDKChecks").appending(component: "MacOSX10.15.sdk")

    // Check -clang-target is on by default when explicit module is on.
    try withTemporaryDirectory { path in
      let main = path.appending(component: "Foo.swift")
      try localFileSystem.writeFileContents(main, bytes: "import Swift")
      var driver = try Driver(args: ["swiftc", "-explicit-module-build",
                                     "-target", "arm64-apple-macos10.14",
                                     "-sdk", sdkRoot.pathString,
                                     main.pathString])
      guard driver.isFrontendArgSupported(.clangTarget) else {
        throw XCTSkip("Skipping: compiler does not support '-clang-target'")
      }
      let plannedJobs = try driver.planBuild()
      XCTAssertTrue(plannedJobs.contains { job in
        job.commandLine.contains(subsequence: [.flag("-clang-target"), .flag("arm64-apple-macos10.15")])
      })
    }

    // Check -clang-target is handled correctly with the MacCatalyst remap.
    try withTemporaryDirectory { path in
      let main = path.appending(component: "Foo.swift")
      try localFileSystem.writeFileContents(main, bytes:
        """
        import Swift
        """
      )
      var driver = try Driver(args: ["swiftc", "-explicit-module-build",
                                     "-target", "arm64e-apple-ios13.0-macabi",
                                     "-sdk", sdkRoot.pathString,
                                     main.pathString])
      guard driver.isFrontendArgSupported(.clangTarget) else {
        throw XCTSkip("Skipping: compiler does not support '-clang-target'")
      }
      let plannedJobs = try driver.planBuild()
      XCTAssertTrue(plannedJobs.contains { job in
        job.commandLine.contains(subsequence: [.flag("-clang-target"), .flag("arm64e-apple-ios13.3-macabi")])
      })
    }

    // Check -disable-clang-target works
    try withTemporaryDirectory { path in
      let main = path.appending(component: "Foo.swift")
      try localFileSystem.writeFileContents(main, bytes: "import Swift")
      var driver = try Driver(args: ["swiftc", "-disable-clang-target",
                                     "-explicit-module-build",
                                     "-target", "arm64-apple-macos10.14",
                                     "-sdk", sdkRoot.pathString,
                                     main.pathString])
      guard driver.isFrontendArgSupported(.clangTarget) else {
        throw XCTSkip("Skipping: compiler does not support '-clang-target'")
      }
      let plannedJobs = try driver.planBuild()
      XCTAssertFalse(plannedJobs.contains { job in
        job.commandLine.contains(.flag("-clang-target"))
      })
    }
    #endif
  }

  func testDisableClangTargetForImplicitModule() throws {
#if os(macOS)
    var envVars = ProcessEnv.vars
    envVars["SWIFT_DRIVER_LD_EXEC"] = ld.nativePathString(escaped: false)

    let sdkRoot = try testInputsPath.appending(component: "SDKChecks").appending(component: "iPhoneOS.sdk")
    var driver = try Driver(args: ["swiftc", "-target",
                                   "arm64-apple-ios12.0", "foo.swift",
                                   "-sdk", sdkRoot.pathString],
                            env: envVars)
    let plannedJobs = try driver.planBuild()
    XCTAssertEqual(plannedJobs.count, 2)
    XCTAssertTrue(plannedJobs[0].commandLine.contains(.flag("-target")))
    XCTAssertFalse(plannedJobs[0].commandLine.contains(.flag("-clang-target")))
#endif
  }

  func testPCHasCompileInput() throws {
    var envVars = ProcessEnv.vars
    envVars["SWIFT_DRIVER_LD_EXEC"] = ld.nativePathString(escaped: false)

    var driver = try Driver(args: ["swiftc", "-target", "x86_64-apple-macosx10.14", "-enable-bridging-pch", "-import-objc-header", "TestInputHeader.h", "foo.swift"],
                            env: envVars)
    let plannedJobs = try driver.planBuild()
    XCTAssertEqual(plannedJobs.count, 3)
    XCTAssert(plannedJobs[0].kind == .generatePCH)
    XCTAssert(plannedJobs[1].kind == .compile)
    XCTAssert(plannedJobs[1].inputs[0].file.extension == "swift")
    XCTAssert(plannedJobs[1].inputs[1].file.extension == "pch")
  }

  func testEnvironmentInferenceWarning() throws {
    let sdkRoot = try testInputsPath.appending(component: "SDKChecks").appending(component: "iPhoneOS.sdk")

    try assertDriverDiagnostics(args: ["swiftc", "-target", "x86_64-apple-ios13.0", "foo.swift", "-sdk", sdkRoot.pathString]) {
      $1.expect(.warning("inferring simulator environment for target 'x86_64-apple-ios13.0'; use '-target x86_64-apple-ios13.0-simulator'"))
    }
    try assertDriverDiagnostics(args: ["swiftc", "-target", "x86_64-apple-watchos6.0", "foo.swift", "-sdk", sdkRoot.pathString]) {
      $1.expect(.warning("inferring simulator environment for target 'x86_64-apple-watchos6.0'; use '-target x86_64-apple-watchos6.0-simulator'"))
    }
    try assertNoDriverDiagnostics(args: "swiftc", "-target", "x86_64-apple-ios13.0-simulator", "foo.swift", "-sdk", sdkRoot.pathString)
  }

  func testDarwinToolchainArgumentValidation() throws {
    XCTAssertThrowsError(try Driver(args: ["swiftc", "-c", "-target", "arm64-apple-ios6.0",
                                           "foo.swift"])) { error in
      guard case DarwinToolchain.ToolchainValidationError.osVersionBelowMinimumDeploymentTarget(platform: .iOS(.device), version: Triple.Version(7, 0, 0)) = error else {
        XCTFail("Unexpected error: \(error)")
        return
      }
    }

    XCTAssertThrowsError(try Driver(args: ["swiftc", "-c", "-target", "x86_64-apple-ios6.0-simulator",
                                           "foo.swift"])) { error in
      guard case DarwinToolchain.ToolchainValidationError.osVersionBelowMinimumDeploymentTarget(platform: .iOS(.simulator), version: Triple.Version(7, 0, 0)) = error else {
        XCTFail("Unexpected error: \(error)")
        return
      }
    }

    XCTAssertThrowsError(try Driver(args: ["swiftc", "-c", "-target", "arm64-apple-tvos6.0",
                                           "foo.swift"])) { error in
      guard case DarwinToolchain.ToolchainValidationError.osVersionBelowMinimumDeploymentTarget(platform: .tvOS(.device), version: Triple.Version(9, 0, 0)) = error else {
        XCTFail("Unexpected error: \(error)")
        return
      }
    }

    XCTAssertThrowsError(try Driver(args: ["swiftc", "-c", "-target", "x86_64-apple-tvos6.0-simulator",
                                           "foo.swift"])) { error in
      guard case DarwinToolchain.ToolchainValidationError.osVersionBelowMinimumDeploymentTarget(platform: .tvOS(.simulator), version: Triple.Version(9, 0, 0)) = error else {
        XCTFail("Unexpected error: \(error)")
        return
      }
    }

    XCTAssertThrowsError(try Driver(args: ["swiftc", "-c", "-target", "arm64-apple-watchos1.0",
                                           "foo.swift"])) { error in
      guard case DarwinToolchain.ToolchainValidationError.osVersionBelowMinimumDeploymentTarget(platform: .watchOS(.device), version: Triple.Version(2, 0, 0)) = error else {
        XCTFail("Unexpected error: \(error)")
        return
      }
    }

    XCTAssertThrowsError(try Driver(args: ["swiftc", "-c", "-target", "x86_64-apple-watchos1.0-simulator",
                                           "foo.swift"])) { error in
      guard case DarwinToolchain.ToolchainValidationError.osVersionBelowMinimumDeploymentTarget(platform: .watchOS(.simulator), version: Triple.Version(2, 0, 0)) = error else {
        XCTFail("Unexpected error: \(error)")
        return
      }
    }

    XCTAssertThrowsError(try Driver(args: ["swiftc", "-c", "-target", "x86_64-apple-macosx10.4",
                                           "foo.swift"])) { error in
      guard case DarwinToolchain.ToolchainValidationError.osVersionBelowMinimumDeploymentTarget(platform: .macOS, version: Triple.Version(10, 9, 0)) = error else {
        XCTFail("Unexpected error: \(error)")
        return
      }
    }

    XCTAssertThrowsError(try Driver(args: ["swiftc", "-c", "-target", "armv7-apple-ios12.1",
                                           "foo.swift"])) { error in
      guard case DarwinToolchain.ToolchainValidationError.invalidDeploymentTargetForIR(platform: .iOS(.device), version: Triple.Version(11, 0, 0), archName: "armv7") = error else {
        XCTFail("Unexpected error: \(error)")
        return
      }
    }

    XCTAssertThrowsError(try Driver(args: ["swiftc", "-emit-module", "-c", "-target",
                                           "armv7s-apple-ios12.0", "foo.swift"])) { error in
      guard case DarwinToolchain.ToolchainValidationError.invalidDeploymentTargetForIR(platform: .iOS(.device), version: Triple.Version(11, 0, 0), archName: "armv7s") = error else {
        XCTFail("Unexpected error: \(error)")
        return
      }
    }

    XCTAssertThrowsError(try Driver(args: ["swiftc", "-emit-module", "-c", "-target",
                                           "i386-apple-ios12.0-simulator", "foo.swift"])) { error in
      guard case DarwinToolchain.ToolchainValidationError.invalidDeploymentTargetForIR(platform: .iOS(.simulator), version: Triple.Version(11, 0, 0), archName: "i386") = error else {
        XCTFail("Unexpected error: \(error)")
        return
      }
    }

    XCTAssertThrowsError(try Driver(args: ["swiftc", "-emit-module", "-c", "-target",
                                             "armv7k-apple-watchos12.0", "foo.swift"])) { error in
      guard case DarwinToolchain.ToolchainValidationError.invalidDeploymentTargetForIR(platform: .watchOS(.device), version: Triple.Version(9, 0, 0), archName: "armv7k") = error else {
        XCTFail("Unexpected error: \(error)")
        return
      }
    }

    XCTAssertThrowsError(try Driver(args: ["swiftc", "-emit-module", "-c", "-target",
                                           "i386-apple-watchos12.0", "foo.swift"])) { error in
      guard case DarwinToolchain.ToolchainValidationError.invalidDeploymentTargetForIR(platform: .watchOS(.simulator), version: Triple.Version(7, 0, 0), archName: "i386") = error else {
        XCTFail("Unexpected error: \(error)")
        return
      }
    }

    XCTAssertThrowsError(try Driver(args: ["swiftc", "-c", "-target", "x86_64-apple-ios13.0",
                                           "-target-variant", "x86_64-apple-macosx10.14",
                                           "foo.swift"])) { error in
      guard case DarwinToolchain.ToolchainValidationError.unsupportedTargetVariant(variant: _) = error else {
        XCTFail("Unexpected error: \(error)")
        return
      }
    }

    XCTAssertThrowsError(try Driver(args: ["swiftc", "-c", "-static-stdlib", "-target", "x86_64-apple-macosx10.14",
                                           "foo.swift"])) { error in
      guard case DarwinToolchain.ToolchainValidationError.argumentNotSupported("-static-stdlib") = error else {
        XCTFail("Unexpected error: \(error)")
        return
      }
    }

    XCTAssertThrowsError(try Driver(args: ["swiftc", "-c", "-static-executable", "-target", "x86_64-apple-macosx10.14",
                                           "foo.swift"])) { error in
      guard case DarwinToolchain.ToolchainValidationError.argumentNotSupported("-static-executable") = error else {
        XCTFail("Unexpected error: \(error)")
        return
      }
    }

    XCTAssertThrowsError(try Driver(args: ["swiftc", "-c", "-target", "x86_64-apple-macosx10.14", "-experimental-cxx-stdlib", "libstdc++",
                                           "foo.swift"])) { error in
        guard case DarwinToolchain.ToolchainValidationError.darwinOnlySupportsLibCxx = error else {
          XCTFail("Unexpected error: \(error)")
        return
      }
    }

    // Not actually a valid arch for tvOS, but we shouldn't fall into the iOS case by mistake and emit a message about iOS >= 11 not supporting armv7.
    XCTAssertNoThrow(try Driver(args: ["swiftc", "-c", "-target", "armv7-apple-tvos9.0", "foo.swift"]))

    // Ensure arm64_32 is not restricted to back-deployment like other 32-bit archs (armv7k/i386).
    XCTAssertNoThrow(try Driver(args: ["swiftc", "-emit-module", "-c", "-target", "arm64_32-apple-watchos12.0", "foo.swift"]))

    // On non-darwin hosts, libArcLite won't be found and a warning will be emitted
    #if os(macOS)
    try assertNoDriverDiagnostics(args: "swiftc", "-c", "-target", "x86_64-apple-macosx10.14", "-link-objc-runtime", "foo.swift")
    #endif
  }

  func testProfileArgValidation() throws {
    try assertDriverDiagnostics(args: ["swiftc", "foo.swift", "-profile-generate", "-profile-use=profile.profdata"]) {
      $1.expect(.error(Driver.Error.conflictingOptions(.profileGenerate, .profileUse)))
      $1.expect(.error(Driver.Error.missingProfilingData(try toPath("profile.profdata").name)))
    }

    try assertDriverDiagnostics(args: ["swiftc", "foo.swift", "-profile-use=profile.profdata"]) {
      $1.expect(.error(Driver.Error.missingProfilingData(try toPath("profile.profdata").name)))
    }

    try withTemporaryDirectory { path in
      try localFileSystem.writeFileContents(path.appending(component: "profile.profdata"), bytes: .init())
      try assertNoDriverDiagnostics(args: "swiftc", "-working-directory", path.pathString, "foo.swift", "-profile-use=profile.profdata")
    }

    try withTemporaryDirectory { path in
      try localFileSystem.writeFileContents(path.appending(component: "profile.profdata"), bytes: .init())
      try assertDriverDiagnostics(args: ["swiftc", "-working-directory", path.pathString, "foo.swift",
                                         "-profile-use=profile.profdata,profile2.profdata"]) {
        $1.expect(.error(Driver.Error.missingProfilingData(path.appending(component: "profile2.profdata").pathString)))
      }
    }
  }

  func testProfileLinkerArgs() throws {
    var envVars = ProcessEnv.vars
    envVars["SWIFT_DRIVER_LD_EXEC"] = ld.nativePathString(escaped: false)

    do {
      var driver = try Driver(args: ["swiftc", "-profile-generate", "-target", "x86_64-apple-macosx10.9", "test.swift"],
                              env: envVars)
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 2)
      XCTAssertEqual(plannedJobs[0].kind, .compile)

      XCTAssertEqual(plannedJobs[1].kind, .link)
      XCTAssert(plannedJobs[1].commandLine.contains(.flag("-fprofile-generate")))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-profile-generate", "-target", "x86_64-apple-ios7.1-simulator", "test.swift"],
                              env: envVars)
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 2)
      XCTAssertEqual(plannedJobs[0].kind, .compile)

      XCTAssertEqual(plannedJobs[1].kind, .link)
      XCTAssert(plannedJobs[1].commandLine.contains(.flag("-fprofile-generate")))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-profile-generate", "-target", "arm64-apple-ios7.1", "test.swift"],
                              env: envVars)
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 2)
      XCTAssertEqual(plannedJobs[0].kind, .compile)

      XCTAssertEqual(plannedJobs[1].kind, .link)
      XCTAssert(plannedJobs[1].commandLine.contains(.flag("-fprofile-generate")))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-profile-generate", "-target", "x86_64-apple-tvos9.0-simulator", "test.swift"],
                              env: envVars)
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 2)
      XCTAssertEqual(plannedJobs[0].kind, .compile)

      XCTAssertEqual(plannedJobs[1].kind, .link)
      XCTAssert(plannedJobs[1].commandLine.contains(.flag("-fprofile-generate")))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-profile-generate", "-target", "arm64-apple-tvos9.0", "test.swift"],
                              env: envVars)
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 2)
      XCTAssertEqual(plannedJobs[0].kind, .compile)

      XCTAssertEqual(plannedJobs[1].kind, .link)
      XCTAssert(plannedJobs[1].commandLine.contains(.flag("-fprofile-generate")))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-profile-generate", "-target", "i386-apple-watchos2.0-simulator", "test.swift"],
                              env: envVars)
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 2)
      XCTAssertEqual(plannedJobs[0].kind, .compile)

      XCTAssertEqual(plannedJobs[1].kind, .link)
      XCTAssert(plannedJobs[1].commandLine.contains(.flag("-fprofile-generate")))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-profile-generate", "-target", "armv7k-apple-watchos2.0", "test.swift"],
                              env: envVars)
      let plannedJobs = try driver.planBuild()

      XCTAssertEqual(plannedJobs.count, 2)
      XCTAssertEqual(plannedJobs[0].kind, .compile)

      XCTAssertEqual(plannedJobs[1].kind, .link)
      XCTAssert(plannedJobs[1].commandLine.contains(.flag("-fprofile-generate")))
    }

    // FIXME: This will fail when run on macOS, because
    // swift-autolink-extract is not present
    #if os(Linux) || os(Android) || os(Windows)
    do {
      var driver = try Driver(args: ["swiftc", "-profile-generate", "-target", "x86_64-unknown-linux-gnu", "test.swift"])
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()

      XCTAssertEqual(plannedJobs.count, 2)
      XCTAssertEqual(plannedJobs[0].kind, .compile)

      XCTAssertEqual(plannedJobs[1].kind, .link)
      XCTAssert(plannedJobs[1].commandLine.containsPathWithBasename("libclang_rt.profile-x86_64.a"))
      XCTAssert(plannedJobs[1].commandLine.contains { $0 == .flag("-u__llvm_profile_runtime") })
    }
    #endif

    // TODO: Windows
  }

  func testConditionalCompilationArgValidation() throws {
    try assertDriverDiagnostics(args: ["swiftc", "foo.swift", "-DFOO=BAR"]) {
      $1.expect(.warning("conditional compilation flags do not have values in Swift; they are either present or absent (rather than 'FOO=BAR')"))
    }

    try assertDriverDiagnostics(args: ["swiftc", "foo.swift", "-D-DFOO"]) {
      $1.expect(.error(Driver.Error.conditionalCompilationFlagHasRedundantPrefix("-DFOO")))
    }

    try assertDriverDiagnostics(args: ["swiftc", "foo.swift", "-Dnot-an-identifier"]) {
      $1.expect(.error(Driver.Error.conditionalCompilationFlagIsNotValidIdentifier("not-an-identifier")))
    }

    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-DFOO")
  }

  func testFrameworkSearchPathArgValidation() throws {
    try assertDriverDiagnostics(args: ["swiftc", "foo.swift", "-F/some/dir/xyz.framework"]) {
      $1.expect(.warning("framework search path ends in \".framework\"; add directory containing framework instead: /some/dir/xyz.framework"))
    }

    try assertDriverDiagnostics(args: ["swiftc", "foo.swift", "-F/some/dir/xyz.framework/"]) {
      $1.expect(.warning("framework search path ends in \".framework\"; add directory containing framework instead: /some/dir/xyz.framework"))
    }

    try assertDriverDiagnostics(args: ["swiftc", "foo.swift", "-Fsystem", "/some/dir/xyz.framework"]) {
      $1.expect(.warning("framework search path ends in \".framework\"; add directory containing framework instead: /some/dir/xyz.framework"))
    }

   try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-Fsystem", "/some/dir/")
  }

  func testMultipleValidationFailures() throws {
    try assertDiagnostics { engine, verifier in
      verifier.expect(.error(Driver.Error.conditionalCompilationFlagIsNotValidIdentifier("not-an-identifier")))
      verifier.expect(.warning("framework search path ends in \".framework\"; add directory containing framework instead: /some/dir/xyz.framework"))
      _ = try Driver(args: ["swiftc", "foo.swift", "-Dnot-an-identifier", "-F/some/dir/xyz.framework"], diagnosticsEngine: engine)
    }
  }

  func testToolsDirectory() throws {
    try withTemporaryDirectory { tmpDir in
      let ld = tmpDir.appending(component: executableName("clang"))
      // tiny PE binary from: https://archive.is/w01DO
      let contents: ByteString = [
          0x4d, 0x5a, 0x00, 0x00, 0x50, 0x45, 0x00, 0x00, 0x4c, 0x01, 0x01, 0x00,
          0x6a, 0x2a, 0x58, 0xc3, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
          0x04, 0x00, 0x03, 0x01, 0x0b, 0x01, 0x08, 0x00, 0x04, 0x00, 0x00, 0x00,
          0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x0c, 0x00, 0x00, 0x00,
          0x04, 0x00, 0x00, 0x00, 0x0c, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00,
          0x04, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00,
          0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
          0x68, 0x00, 0x00, 0x00, 0x64, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
          0x02
      ]
      try localFileSystem.writeFileContents(ld, bytes: contents)
      try localFileSystem.chmod(.executable, path: try AbsolutePath(validating: ld.pathString))

      // Drop SWIFT_DRIVER_CLANG_EXEC from the environment so it doesn't
      // interfere with tool lookup.
      var env = ProcessEnv.vars
      env.removeValue(forKey: "SWIFT_DRIVER_CLANG_EXEC")

      var driver = try Driver(args: ["swiftc",
                                     "-tools-directory", tmpDir.pathString,
                                     "foo.swift"],
                              env: env)
      let frontendJobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(frontendJobs.count, 2)
      XCTAssertEqual(frontendJobs[1].kind, .link)
      XCTAssertEqual(frontendJobs[1].tool.absolutePath!.pathString, ld.pathString)

      // WASI toolchain
      do {
        try withTemporaryDirectory { resourceDir in
          try localFileSystem.writeFileContents(resourceDir.appending(components: "wasi", "static-executable-args.lnk")) {
            $0.send("garbage")
          }
          var driver = try Driver(args: ["swiftc",
                                         "-target", "wasm32-unknown-wasi",
                                         "-resource-dir", resourceDir.pathString,
                                         "-tools-directory", tmpDir.pathString,
                                         "foo.swift"],
                                  env: env)
          let frontendJobs = try driver.planBuild().removingAutolinkExtractJobs()
          XCTAssertEqual(frontendJobs.count, 2)
          XCTAssertTrue(frontendJobs[1].commandLine.contains(subsequence: [
            .flag("-B"), .path(.absolute(tmpDir))
          ]))
        }
      }
    }
  }

  func testNonDarwinSDK() throws {
    try withTemporaryDirectory { tmpDir in
      let sdk = tmpDir.appending(component: "NonDarwin.sdk")
      // SDK without SDKSettings.json should be ok for non-Darwin platforms
      try localFileSystem.createDirectory(sdk, recursive: true)
      for triple in ["x86_64-unknown-linux-gnu", "wasm32-unknown-wasi"] {
        try assertDriverDiagnostics(args: "swiftc", "-target", triple, "foo.swift", "-sdk", sdk.pathString) {
          $1.forbidUnexpected(.error, .warning)
        }
      }
    }
  }

  func testDarwinSDKWithoutSDKSettings() throws {
    try withTemporaryDirectory { tmpDir in
      let sdk = tmpDir.appending(component: "MacOSX10.15.sdk")
      try localFileSystem.createDirectory(sdk, recursive: true)
      try assertDriverDiagnostics(args: "swiftc", "-target", "x86_64-apple-macosx10.15", "foo.swift", "-sdk", sdk.pathString) {
        $1.expect(.warning("Could not read SDKSettings.json for SDK at: \(sdk.pathString)"))
      }
    }
  }

  func testDarwinSDKToolchainName() throws {
    var envVars = ProcessEnv.vars
    envVars["SWIFT_DRIVER_LD_EXEC"] = ld.nativePathString(escaped: false)

    try withTemporaryDirectory { tmpDir in
      let sdk = tmpDir.appending(component: "XROS1.0.sdk")
      try localFileSystem.createDirectory(sdk, recursive: true)
      try localFileSystem.writeFileContents(sdk.appending(component: "SDKSettings.json"), bytes:
        """
        {
          "Version":"1.0",
          "CanonicalName": "xros1.0"
        }
        """
      )

      let sdkInfo = DarwinToolchain.readSDKInfo(localFileSystem, VirtualPath.absolute(sdk).intern())
      XCTAssertEqual(sdkInfo?.platformKind, .visionos)
    }
  }

  // Test cases ported from Driver/macabi-environment.swift
  func testDarwinSDKVersioning() throws {
    var envVars = ProcessEnv.vars
    envVars["SWIFT_DRIVER_LD_EXEC"] = ld.nativePathString(escaped: false)

    try withTemporaryDirectory { tmpDir in
      let sdk1 = tmpDir.appending(component: "MacOSX10.15.sdk")
      try localFileSystem.createDirectory(sdk1, recursive: true)
      try localFileSystem.writeFileContents(sdk1.appending(component: "SDKSettings.json"), bytes:
        """
        {
          "Version":"10.15",
          "CanonicalName": "macosx10.15",
          "VersionMap" : {
              "macOS_iOSMac" : {
                  "10.15" : "13.1",
                  "10.15.1" : "13.2"
              },
              "iOSMac_macOS" : {
                  "13.1" : "10.15",
                  "13.2" : "10.15.1"
              }
          }
        }
        """
      )

      let sdk2 = tmpDir.appending(component: "MacOSX10.15.4.sdk")
      try localFileSystem.createDirectory(sdk2, recursive: true)
      try localFileSystem.writeFileContents(sdk2.appending(component: "SDKSettings.json"), bytes:
        """
        {
          "Version":"10.15.4",
          "CanonicalName": "macosx10.15.4",
          "VersionMap" : {
              "macOS_iOSMac" : {
                  "10.14.4" : "12.4",
                  "10.14.3" : "12.3",
                  "10.14.2" : "12.2",
                  "10.14.1" : "12.1",
                  "10.15" : "13.0",
                  "10.14" : "12.0",
                  "10.14.5" : "12.5",
                  "10.15.1" : "13.2",
                  "10.15.4" : "13.4"
              },
              "iOSMac_macOS" : {
                  "13.0" : "10.15",
                  "12.3" : "10.14.3",
                  "12.0" : "10.14",
                  "12.4" : "10.14.4",
                  "12.1" : "10.14.1",
                  "12.5" : "10.14.5",
                  "12.2" : "10.14.2",
                  "13.2" : "10.15.1",
                  "13.4" : "10.15.4"
              }
          }
        }
        """
      )

      do {
        var driver = try Driver(args: ["swiftc",
                                       "-target", "x86_64-apple-macosx10.14",
                                       "-sdk", sdk1.description,
                                       "foo.swift"], env: envVars)
        let frontendJobs = try driver.planBuild()
        XCTAssertEqual(frontendJobs[0].kind, .compile)
        XCTAssertTrue(frontendJobs[0].commandLine.contains(subsequence: [
          .flag("-target-sdk-version"),
          .flag("10.15")
        ]))
        if driver.isFrontendArgSupported(.targetSdkName) {
          XCTAssertTrue(frontendJobs[0].commandLine.contains(subsequence: [
            .flag("-target-sdk-name"),
            .flag("macosx10.15"),
          ]))
        }
        XCTAssertEqual(frontendJobs[1].kind, .link)
        XCTAssertTrue(frontendJobs[1].commandLine.contains(.flag("--target=x86_64-apple-macosx10.14")))
        XCTAssertTrue(frontendJobs[1].commandLine.contains(.flag("--sysroot")))
        XCTAssertTrue(frontendJobs[1].commandLine.containsPathWithBasename(sdk1.basename))
      }

      do {
        var envVars = ProcessEnv.vars
        envVars["SWIFT_DRIVER_LD_EXEC"] = ld.nativePathString(escaped: false)

        var driver = try Driver(args: ["swiftc",
                                       "-target", "x86_64-apple-macosx10.14",
                                       "-target-variant", "x86_64-apple-ios13.1-macabi",
                                       "-sdk", sdk1.description,
                                       "foo.swift"], env: envVars)
        let frontendJobs = try driver.planBuild()
        XCTAssertEqual(frontendJobs[0].kind, .compile)
        XCTAssertTrue(frontendJobs[0].commandLine.contains(subsequence: [
          .flag("-target-sdk-version"),
          .flag("10.15"),
          .flag("-target-variant-sdk-version"),
          .flag("13.1"),
        ]))
        XCTAssertEqual(frontendJobs[1].kind, .link)
        XCTAssertTrue(frontendJobs[1].commandLine.contains(.flag("--target=x86_64-apple-macosx10.14")))
        XCTAssertTrue(frontendJobs[1].commandLine.contains(.flag("-darwin-target-variant=x86_64-apple-ios13.1-macabi")))
      }

      do {
        var driver = try Driver(args: ["swiftc",
                                       "-target", "x86_64-apple-macosx10.14",
                                       "-target-variant", "x86_64-apple-ios13.1-macabi",
                                       "-sdk", sdk2.description,
                                       "foo.swift"], env: envVars)
        let frontendJobs = try driver.planBuild()
        XCTAssertEqual(frontendJobs[0].kind, .compile)
        XCTAssertTrue(frontendJobs[0].commandLine.contains(subsequence: [
          .flag("-target-sdk-version"),
          .flag("10.15.4"),
          .flag("-target-variant-sdk-version"),
          .flag("13.4")
        ]))
        if driver.isFrontendArgSupported(.targetSdkName) {
          XCTAssertTrue(frontendJobs[0].commandLine.contains(subsequence: [
            .flag("-target-sdk-name"),
            .flag("macosx10.15.4"),
          ]))
        }
        XCTAssertEqual(frontendJobs[1].kind, .link)
        XCTAssertTrue(frontendJobs[1].commandLine.contains(.flag("--target=x86_64-apple-macosx10.14")))
        XCTAssertTrue(frontendJobs[1].commandLine.contains(.flag("-darwin-target-variant=x86_64-apple-ios13.1-macabi")))
      }

      do {
        var envVars = ProcessEnv.vars
        envVars["SWIFT_DRIVER_LD_EXEC"] = ld.nativePathString(escaped: false)

        var driver = try Driver(args: ["swiftc",
                                       "-target-variant", "x86_64-apple-macosx10.14",
                                       "-target", "x86_64-apple-ios13.1-macabi",
                                       "-sdk", sdk2.description,
                                       "foo.swift"], env: envVars)
        let frontendJobs = try driver.planBuild()
        XCTAssertEqual(frontendJobs[0].kind, .compile)
        XCTAssertTrue(frontendJobs[0].commandLine.contains(subsequence: [
          .flag("-target-sdk-version"),
          .flag("13.4"),
          .flag("-target-variant-sdk-version"),
          .flag("10.15.4")
        ]))
        XCTAssertEqual(frontendJobs[1].kind, .link)
        XCTAssertTrue(frontendJobs[1].commandLine.contains(.flag("--target=x86_64-apple-ios13.1-macabi")))
        XCTAssertTrue(frontendJobs[1].commandLine.contains(.flag("-darwin-target-variant=x86_64-apple-macosx10.14")))
      }
    }
  }

  func testDarwinSDKTooOld() throws {
    func getSDKPath(sdkDirName: String) throws -> AbsolutePath {
      return try testInputsPath.appending(component: "SDKChecks").appending(component: sdkDirName)
    }

    // Ensure an error is emitted for an unsupported SDK
    func checkSDKUnsupported(sdkDirName: String)
    throws {
      let sdkPath = try getSDKPath(sdkDirName: sdkDirName)
      // Get around the check for SDK's existence
      try localFileSystem.createDirectory(sdkPath)
      let args = [ "swiftc", "foo.swift", "-target", "x86_64-apple-macosx10.9", "-sdk", sdkPath.pathString ]
      try assertDriverDiagnostics(args: args) { driver, verifier in
        verifier.expect(.error("Swift does not support the SDK \(sdkPath.pathString)"))
      }
    }

    // Ensure no error is emitted for a supported SDK
    func checkSDKOkay(sdkDirName: String) throws {
      let sdkPath = try getSDKPath(sdkDirName: sdkDirName)
      try localFileSystem.createDirectory(sdkPath)
      let args = [ "swiftc", "foo.swift", "-target", "x86_64-apple-macosx10.9", "-sdk", sdkPath.pathString ]
      try assertNoDiagnostics { de in let _ = try Driver(args: args, diagnosticsEngine: de) }
    }

    // Ensure old/bogus SDK versions are caught
    try checkSDKUnsupported(sdkDirName: "tvOS8.0.sdk")
    try checkSDKUnsupported(sdkDirName: "MacOSX10.8.sdk")
    try checkSDKUnsupported(sdkDirName: "MacOSX10.9.sdk")
    try checkSDKUnsupported(sdkDirName: "MacOSX10.10.sdk")
    try checkSDKUnsupported(sdkDirName: "MacOSX10.11.sdk")
    try checkSDKUnsupported(sdkDirName: "MacOSX7.17.sdk")
    try checkSDKUnsupported(sdkDirName: "MacOSX10.14.Internal.sdk")
    try checkSDKUnsupported(sdkDirName: "iPhoneOS7.sdk")
    try checkSDKUnsupported(sdkDirName: "iPhoneSimulator7.sdk")
    try checkSDKUnsupported(sdkDirName: "iPhoneOS12.99.sdk")
    try checkSDKUnsupported(sdkDirName: "watchOS2.0.sdk")
    try checkSDKUnsupported(sdkDirName: "watchOS3.0.sdk")
    try checkSDKUnsupported(sdkDirName: "watchOS3.0.Internal.sdk")

    // Verify a selection of okay SDKs
    try checkSDKOkay(sdkDirName: "MacOSX10.15.sdk")
    try checkSDKOkay(sdkDirName: "MacOSX10.15.4.sdk")
    try checkSDKOkay(sdkDirName: "MacOSX10.15.Internal.sdk")
    try checkSDKOkay(sdkDirName: "iPhoneOS13.0.sdk")
    try checkSDKOkay(sdkDirName: "tvOS13.0.sdk")
    try checkSDKOkay(sdkDirName: "watchOS6.0.sdk")
    try checkSDKOkay(sdkDirName: "watchSimulator6.0.sdk")
    try checkSDKOkay(sdkDirName: "iPhoneOS.sdk")
    try checkSDKOkay(sdkDirName: "tvOS.sdk")
    try checkSDKOkay(sdkDirName: "watchOS.sdk")
  }

  func testDarwinLinkerPlatformVersion() throws {
    var envVars = ProcessEnv.vars
    envVars["SWIFT_DRIVER_LD_EXEC"] = ld.nativePathString(escaped: false)

    do {
      var driver = try Driver(args: ["swiftc",
                                     "-target", "x86_64-apple-macos10.15",
                                     "foo.swift"],
                              env: envVars)
      let frontendJobs = try driver.planBuild()

      XCTAssertEqual(frontendJobs[1].kind, .link)
      XCTAssertTrue(frontendJobs[1].commandLine.contains(.flag("--target=x86_64-apple-macos10.15")))
    }

    // Mac gained aarch64 support in v11
    do {
      var driver = try Driver(args: ["swiftc",
                                     "-target", "arm64-apple-macos10.15",
                                     "foo.swift"],
                              env: envVars)
      let frontendJobs = try driver.planBuild()

      XCTAssertEqual(frontendJobs[1].kind, .link)
      XCTAssertTrue(frontendJobs[1].commandLine.contains(.flag("--target=arm64-apple-macos10.15")))
    }

    // Mac Catalyst on x86_64 was introduced in v13.
    do {
      var driver = try Driver(args: ["swiftc",
                                     "-target", "x86_64-apple-ios12.0-macabi",
                                     "foo.swift"],
                              env: envVars)
      let frontendJobs = try driver.planBuild()

      XCTAssertEqual(frontendJobs[1].kind, .link)
      XCTAssertTrue(frontendJobs[1].commandLine.contains(.flag("--target=x86_64-apple-ios12.0-macabi")))
    }

    // Mac Catalyst on arm was introduced in v14.
    do {
      var driver = try Driver(args: ["swiftc",
                                     "-target", "aarch64-apple-ios12.0-macabi",
                                     "foo.swift"],
                              env: envVars)
      let frontendJobs = try driver.planBuild()

      XCTAssertEqual(frontendJobs[1].kind, .link)
      XCTAssertTrue(frontendJobs[1].commandLine.contains(.flag("--target=aarch64-apple-ios12.0-macabi")))
    }

    // Regular iOS
    do {
      var driver = try Driver(args: ["swiftc",
                                     "-target", "aarch64-apple-ios12.0",
                                     "foo.swift"],
                              env: envVars)
      let frontendJobs = try driver.planBuild()

      XCTAssertEqual(frontendJobs[1].kind, .link)
      XCTAssertTrue(frontendJobs[1].commandLine.contains(.flag("--target=aarch64-apple-ios12.0")))
    }

    // Regular tvOS
    do {
      var driver = try Driver(args: ["swiftc",
                                     "-target", "aarch64-apple-tvos12.0",
                                     "foo.swift"],
                              env: envVars)
      let frontendJobs = try driver.planBuild()

      XCTAssertEqual(frontendJobs[1].kind, .link)
      XCTAssertTrue(frontendJobs[1].commandLine.contains(.flag("--target=aarch64-apple-tvos12.0")))
    }

    // Regular watchOS
    do {
      var driver = try Driver(args: ["swiftc",
                                     "-target", "aarch64-apple-watchos6.0",
                                     "foo.swift"],
                              env: envVars)
      let frontendJobs = try driver.planBuild()

      XCTAssertEqual(frontendJobs[1].kind, .link)
      XCTAssertTrue(frontendJobs[1].commandLine.contains(.flag("--target=aarch64-apple-watchos6.0")))
    }

    // x86_64 iOS simulator
    do {
      var driver = try Driver(args: ["swiftc",
                                     "-target", "x86_64-apple-ios12.0-simulator",
                                     "foo.swift"],
                              env: envVars)
      let frontendJobs = try driver.planBuild()

      XCTAssertEqual(frontendJobs[1].kind, .link)
      XCTAssertTrue(frontendJobs[1].commandLine.contains(.flag("--target=x86_64-apple-ios12.0-simulator")))
    }

    // aarch64 iOS simulator
    do {
      var driver = try Driver(args: ["swiftc",
                                     "-target", "aarch64-apple-ios12.0-simulator",
                                     "foo.swift"],
                              env: envVars)
      let frontendJobs = try driver.planBuild()

      XCTAssertEqual(frontendJobs[1].kind, .link)
      XCTAssertTrue(frontendJobs[1].commandLine.contains(.flag("--target=aarch64-apple-ios12.0-simulator")))
    }
  }

  func testDSYMGeneration() throws {
    let commonArgs = [
      "swiftc", "foo.swift", "bar.swift",
      "-emit-executable", "-module-name", "Test",
    ]

    do {
      // No dSYM generation (no -g)
      var driver = try Driver(args: commonArgs)
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()

      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertFalse(plannedJobs.containsJob(.generateDSYM))
    }

    do {
      // No dSYM generation (-gnone)
      var driver = try Driver(args: commonArgs + ["-gnone"])
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()

      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertFalse(plannedJobs.containsJob(.generateDSYM))
    }

    do {
      var env = ProcessEnv.vars
      // As per Unix conventions, /var/empty is expected to exist and be empty.
      // This gives us a non-existent path that we can use for libtool which
      // allows us to run this this on non-Darwin platforms.
      env["SWIFT_DRIVER_LIBTOOL_EXEC"] = "/var/empty/libtool"

      // No dSYM generation (-g -emit-library -static)
      var driver = try Driver(args: [
        "swiftc", "-target", "x86_64-apple-macosx10.15", "-g", "-emit-library",
        "-static", "-o", "library.a", "library.swift"
      ], env: env)
      let jobs = try driver.planBuild()

      XCTAssertEqual(jobs.count, 3)
      XCTAssertFalse(jobs.containsJob(.generateDSYM))
    }

    do {
      // dSYM generation (-g)
      var driver = try Driver(args: commonArgs + ["-g"])
      let plannedJobs = try driver.planBuild()

      let generateDSYMJob = plannedJobs.last!
      let cmd = generateDSYMJob.commandLine

      if driver.targetTriple.objectFormat == .elf  {
        XCTAssertEqual(plannedJobs.count, 6)
      } else {
        XCTAssertEqual(plannedJobs.count, 5)
      }

      if driver.targetTriple.isDarwin {
        XCTAssertEqual(generateDSYMJob.outputs.last?.file, try toPath("Test.dSYM"))
      } else {
        XCTAssertFalse(plannedJobs.map { $0.kind }.contains(.generateDSYM))
      }

      XCTAssertTrue(cmd.contains(try toPathOption(executableName("Test"))))
    }

    do {
      // dSYM generation (-g) with specified output file name with an extension
      var driver = try Driver(args: commonArgs + ["-g", "-o", "a.out"])
      let plannedJobs = try driver.planBuild()
      let generateDSYMJob = plannedJobs.last!
      if driver.targetTriple.isDarwin {
        XCTAssertEqual(plannedJobs.count, 5)
        XCTAssertEqual(generateDSYMJob.outputs.last?.file, try toPath("a.out.dSYM"))
      }
    }
  }

  func testEmitModuleTrace() throws {
    do {
      var driver = try Driver(args: ["swiftc", "-typecheck", "-emit-loaded-module-trace", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      let job = plannedJobs[0]
      XCTAssertTrue(
        job.commandLine.contains(subsequence: ["-emit-loaded-module-trace-path",
                                               .path(.relative(try .init(validating: "foo.trace.json")))])
      )
    }
    do {
      var driver = try Driver(args: ["swiftc", "-typecheck",
                                     "-emit-loaded-module-trace",
                                     "foo.swift", "bar.swift", "baz.swift"])
      let plannedJobs = try driver.planBuild()
      let tracedJobs = try plannedJobs.filter {
        $0.commandLine.contains(subsequence: ["-emit-loaded-module-trace-path",
                                              .path(.relative(try .init(validating: "main.trace.json")))])
      }
      XCTAssertEqual(tracedJobs.count, 1)
    }
    do {
      // Make sure the trace is associated with the first frontend job as
      // opposed to the first input.
      var driver = try Driver(args: ["swiftc", "-emit-loaded-module-trace",
                                     "foo.o", "bar.swift", "baz.o"])
      let plannedJobs = try driver.planBuild()
      let tracedJobs = try plannedJobs.filter {
        $0.commandLine.contains(subsequence: ["-emit-loaded-module-trace-path",
                                              .path(.relative(try .init(validating: "main.trace.json")))])
      }
      XCTAssertEqual(tracedJobs.count, 1)
      XCTAssertTrue(tracedJobs[0].inputs.contains(.init(file: try toPath("bar.swift").intern(), type: .swift)))
    }
    do {
      var env = ProcessEnv.vars
      env["SWIFT_LOADED_MODULE_TRACE_FILE"] = "/some/path/to/the.trace.json"
      var driver = try Driver(args: ["swiftc", "-typecheck",
                                     "-emit-loaded-module-trace", "foo.swift"],
                              env: env)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      let job = plannedJobs[0]
      XCTAssertTrue(
        job.commandLine.contains(subsequence: ["-emit-loaded-module-trace-path",
                                               .path(.absolute(try .init(validating: "/some/path/to/the.trace.json")))])
      )
    }
  }

  func testVerifyDebugInfo() throws {
    let commonArgs = [
      "swiftc", "foo.swift", "bar.swift",
      "-emit-executable", "-module-name", "Test", "-verify-debug-info"
    ]

    // No dSYM generation (no -g), therefore no verification
    try assertDriverDiagnostics(args: commonArgs) { driver, verifier in
      verifier.expect(.warning("ignoring '-verify-debug-info'; no debug info is being generated"))
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertFalse(plannedJobs.containsJob(.verifyDebugInfo))
    }

    // No dSYM generation (-gnone), therefore no verification
    try assertDriverDiagnostics(args: commonArgs + ["-gnone"]) { driver, verifier in
      verifier.expect(.warning("ignoring '-verify-debug-info'; no debug info is being generated"))
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(plannedJobs.count, 3)
      XCTAssertFalse(plannedJobs.containsJob(.verifyDebugInfo))
    }

    do {
      // dSYM generation and verification (-g + -verify-debug-info)
      var driver = try Driver(args: commonArgs + ["-g"])
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()

      let verifyDebugInfoJob = plannedJobs.last!
      let cmd = verifyDebugInfoJob.commandLine

      if driver.targetTriple.isDarwin {
        XCTAssertEqual(plannedJobs.count, 6)
        XCTAssertEqual(verifyDebugInfoJob.inputs.first?.file, try toPath("Test.dSYM"))
        XCTAssertTrue(cmd.contains(.flag("--verify")))
        XCTAssertTrue(cmd.contains(.flag("--debug-info")))
        XCTAssertTrue(cmd.contains(.flag("--eh-frame")))
        XCTAssertTrue(cmd.contains(.flag("--quiet")))
        XCTAssertTrue(cmd.contains(try toPathOption("Test.dSYM")))
      } else {
        XCTAssertEqual(plannedJobs.count, 5)
      }
    }
  }

  func testLEqualPassedDownToLinkerInvocation() throws {
    let workingDirectory = localFileSystem.currentWorkingDirectory!.appending(components: "Foo", "Bar")

    var driver = try Driver(args: [
      "swiftc", "-working-directory", workingDirectory.pathString, "-emit-executable", "test.swift", "-L=.", "-F=."
    ])
    let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
    let workDir: VirtualPath = try VirtualPath(path: workingDirectory.nativePathString(escaped: false))

    XCTAssertEqual(plannedJobs.count, 2)
    XCTAssertTrue(plannedJobs[0].commandLine.contains(.joinedOptionAndPath("-F=", workDir)))
    XCTAssertFalse(plannedJobs[0].commandLine.contains(.joinedOptionAndPath("-L=", workDir)))
    XCTAssertTrue(plannedJobs[1].commandLine.contains(.joinedOptionAndPath("-L=", workDir)))
    XCTAssertFalse(plannedJobs[1].commandLine.contains(.joinedOptionAndPath("-F=", workDir)))
    // Test implicit output file also honors the working directory.
    XCTAssertTrue(plannedJobs[1].commandLine.contains(.flag("-o")))
    XCTAssertTrue(plannedJobs[1].commandLine.contains(.path(try VirtualPath(path: rebase(executableName("test"), at: workingDirectory)))))
  }

  func testWorkingDirectoryForImplicitOutputs() throws {
    let workingDirectory = localFileSystem.currentWorkingDirectory!.appending(components: "Foo", "Bar")

    var driver = try Driver(args: [
      "swiftc", "-working-directory", workingDirectory.pathString, "-emit-executable", "-c", "/tmp/main.swift"
    ])
    let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()

    XCTAssertEqual(plannedJobs.count, 1)
    XCTAssertTrue(plannedJobs[0].commandLine.contains(.flag("-o")))
    XCTAssertTrue(plannedJobs[0].commandLine.contains(.path(try VirtualPath(path: rebase("main.o", at: workingDirectory)))))
  }

  func testWorkingDirectoryForImplicitModules() throws {
    let workingDirectory = localFileSystem.currentWorkingDirectory!.appending(components: "Foo", "Bar")

    var driver = try Driver(args: [
      "swiftc", "-working-directory", workingDirectory.pathString, "-emit-module", "/tmp/main.swift"
    ])
    let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()

    XCTAssertEqual(plannedJobs.count, 2)
    XCTAssertTrue(plannedJobs[0].commandLine.contains(.flag("-o")))
    XCTAssertTrue(plannedJobs[0].commandLine.contains(.path(try VirtualPath(path: rebase("main.swiftmodule", at: workingDirectory)))))
    XCTAssertTrue(plannedJobs[0].commandLine.contains(.flag("-emit-module-doc-path")))
    XCTAssertTrue(plannedJobs[0].commandLine.contains(.path(try VirtualPath(path: rebase("main.swiftdoc", at: workingDirectory)))))
    XCTAssertTrue(plannedJobs[0].commandLine.contains(.flag("-emit-module-source-info-path")))
    XCTAssertTrue(plannedJobs[0].commandLine.contains(.path(try VirtualPath(path: rebase("main.swiftsourceinfo", at: workingDirectory)))))
  }

  func testDOTFileEmission() throws {
    // Reset the temporary store to ensure predictable results.
    VirtualPath.resetTemporaryFileStore()
    var driver = try Driver(args: [
      "swiftc", "-emit-executable", "test.swift", "-emit-module", "-avoid-emit-module-source-info", "-experimental-emit-module-separately"
    ])
    let plannedJobs = try driver.planBuild()

    var serializer = DOTJobGraphSerializer(jobs: plannedJobs)
    var output = ""
    serializer.writeDOT(to: &output)

    let linkerDriver = executableName("clang")
    if driver.targetTriple.objectFormat == .elf {
        XCTAssertEqual(output,
        """
        digraph Jobs {
          "emitModule (\(executableName("swift-frontend")))" [style=bold];
          "\rebase("test.swift")" [fontsize=12];
          "\rebase("test.swift")" -> "emitModule (\(executableName("swift-frontend")))" [color=blue];
          "\rebase("test.swiftmodule")" [fontsize=12];
          "emitModule (\(executableName("swift-frontend")))" -> "\rebase("test.swiftmodule")" [color=green];
          "\rebase("test.swiftdoc")" [fontsize=12];
          "emitModule (\(executableName("swift-frontend")))" -> "\rebase("test.swiftdoc")" [color=green];
          "compile (\(executableName("swift-frontend")))" [style=bold];
          "\rebase("test.swift")" -> "compile (\(executableName("swift-frontend")))" [color=blue];
          "test-1.o" [fontsize=12];
          "compile (\(executableName("swift-frontend")))" -> "test-1.o" [color=green];
          "autolinkExtract (\(executableName("swift-autolink-extract")))" [style=bold];
          "test-1.o" -> "autolinkExtract (\(executableName("swift-autolink-extract")))" [color=blue];
          "test-2.autolink" [fontsize=12];
          "autolinkExtract (\(executableName("swift-autolink-extract")))" -> "test-2.autolink" [color=green];
          "link (\(executableName("clang")))" [style=bold];
          "test-1.o" -> "link (\(executableName("clang")))" [color=blue];
          "test-2.autolink" -> "link (\(executableName("clang")))" [color=blue];
          "\(rebase(executableName("test")))" [fontsize=12];
          "link (\(linkerDriver))" -> "\(rebase(executableName("test")))" [color=green];
        }

        """)
    } else if driver.targetTriple.objectFormat == .macho {
        XCTAssertEqual(output,
        """
        digraph Jobs {
          "emitModule (\(executableName("swift-frontend")))" [style=bold];
          "\(rebase("test.swift"))" [fontsize=12];
          "\(rebase("test.swift"))" -> "emitModule (\(executableName("swift-frontend")))" [color=blue];
          "\(rebase("test.swiftmodule"))" [fontsize=12];
          "emitModule (\(executableName("swift-frontend")))" -> "\(rebase("test.swiftmodule"))" [color=green];
          "\(rebase("test.swiftdoc"))" [fontsize=12];
          "emitModule (\(executableName("swift-frontend")))" -> "\(rebase("test.swiftdoc"))" [color=green];
          "\(rebase("test.abi.json"))" [fontsize=12];
          "emitModule (\(executableName("swift-frontend")))" -> "\(rebase("test.abi.json"))" [color=green];
          "compile (\(executableName("swift-frontend")))" [style=bold];
          "\(rebase("test.swift"))" -> "compile (\(executableName("swift-frontend")))" [color=blue];
          "test-1.o" [fontsize=12];
          "compile (\(executableName("swift-frontend")))" -> "test-1.o" [color=green];
          "link (\(linkerDriver))" [style=bold];
          "test-1.o" -> "link (\(linkerDriver))" [color=blue];
          "\(rebase(executableName("test")))" [fontsize=12];
          "link (\(linkerDriver))" -> "\(rebase(executableName("test")))" [color=green];
        }

        """)
    } else {
      XCTAssertEqual(output,
      """
      digraph Jobs {
        "emitModule (\(executableName("swift-frontend")))" [style=bold];
        "\(rebase("test.swift"))" [fontsize=12];
        "\(rebase("test.swift"))" -> "emitModule (\(executableName("swift-frontend")))" [color=blue];
        "\(rebase("test.swiftmodule"))" [fontsize=12];
        "emitModule (\(executableName("swift-frontend")))" -> "\(rebase("test.swiftmodule"))" [color=green];
        "\(rebase("test.swiftdoc"))" [fontsize=12];
        "emitModule (\(executableName("swift-frontend")))" -> "\(rebase("test.swiftdoc"))" [color=green];
        "compile (\(executableName("swift-frontend")))" [style=bold];
        "\(rebase("test.swift"))" -> "compile (\(executableName("swift-frontend")))" [color=blue];
        "test-1.o" [fontsize=12];
        "compile (\(executableName("swift-frontend")))" -> "test-1.o" [color=green];
        "link (\(linkerDriver))" [style=bold];
        "test-1.o" -> "link (\(linkerDriver))" [color=blue];
        "\(rebase(executableName("test")))" [fontsize=12];
        "link (\(linkerDriver))" -> "\(rebase(executableName("test")))" [color=green];
      }

      """)
    }
  }

  func testRegressions() throws {
    var driverWithEmptySDK = try Driver(args: ["swiftc", "-sdk", "", "file.swift"])
    _ = try driverWithEmptySDK.planBuild()

    var driver = try Driver(args: ["swiftc", "foo.swift", "-sdk", "/"])
    let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()

    XCTAssertTrue(plannedJobs[0].commandLine.contains(subsequence: ["-sdk", .path(.absolute(try .init(validating: "/")))]))

    if !driver.targetTriple.isDarwin {
      XCTAssertFalse(plannedJobs[1].commandLine.contains(subsequence: ["-L", .path(.absolute(try .init(validating: "/usr/lib/swift")))]))
    }
  }

  func testDumpASTOverride() throws {
    try assertDriverDiagnostics(args: ["swiftc", "-wmo", "-dump-ast", "foo.swift"]) {
      $1.expect(.warning("ignoring '-wmo' because '-dump-ast' was also specified"))
      let jobs = try $0.planBuild()
      XCTAssertEqual(jobs[0].kind, .compile)
      XCTAssertFalse(jobs[0].commandLine.contains("-wmo"))
      XCTAssertTrue(jobs[0].commandLine.contains("-dump-ast"))
    }

    try assertDriverDiagnostics(args: ["swiftc", "-index-file", "-dump-ast",
                                       "foo.swift",
                                       "-index-file-path", "foo.swift",
                                       "-index-store-path", "store/path",
                                       "-index-ignore-system-modules"]) {
      $1.expect(.warning("ignoring '-index-file' because '-dump-ast' was also specified"))
      let jobs = try $0.planBuild()
      XCTAssertEqual(jobs[0].kind, .compile)
      XCTAssertFalse(jobs[0].commandLine.contains("-wmo"))
      XCTAssertFalse(jobs[0].commandLine.contains("-index-file"))
      XCTAssertFalse(jobs[0].commandLine.contains("-index-file-path"))
      XCTAssertFalse(jobs[0].commandLine.contains("-index-store-path"))
      XCTAssertFalse(jobs[0].commandLine.contains("-index-ignore-stdlib"))
      XCTAssertFalse(jobs[0].commandLine.contains("-index-system-modules"))
      XCTAssertFalse(jobs[0].commandLine.contains("-index-ignore-system-modules"))
      XCTAssertTrue(jobs[0].commandLine.contains("-dump-ast"))
    }
  }

  func testDeriveSwiftDocPath() throws {
    var driver = try Driver(args: [
      "swiftc", "-emit-module", "/tmp/main.swift", "-emit-module-path", "test-ios-macabi.swiftmodule"
    ])
    let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
    XCTAssertEqual(plannedJobs.count, 2)
    XCTAssertTrue(plannedJobs[0].kind == .emitModule)
    XCTAssertTrue(plannedJobs[0].commandLine.contains(.flag("-o")))
    XCTAssertTrue(plannedJobs[0].commandLine.contains(try toPathOption("test-ios-macabi.swiftmodule")))
    XCTAssertTrue(plannedJobs[0].commandLine.contains(.flag("-emit-module-doc-path")))
    XCTAssertTrue(plannedJobs[0].commandLine.contains(try toPathOption("test-ios-macabi.swiftdoc")))
    XCTAssertTrue(plannedJobs[0].commandLine.contains(.flag("-emit-module-source-info-path")))
    XCTAssertTrue(plannedJobs[0].commandLine.contains(try toPathOption("test-ios-macabi.swiftsourceinfo")))
  }

  func testToolchainClangPath() throws {
    // Overriding the swift executable to a specific location breaks this.
    guard ProcessEnv.vars["SWIFT_DRIVER_SWIFT_EXEC"] == nil,
          ProcessEnv.vars["SWIFT_DRIVER_SWIFT_FRONTEND_EXEC"] == nil else {
      return
    }
    // TODO: remove this conditional check once DarwinToolchain does not requires xcrun to look for clang.
    var toolchain: Toolchain
    let executor = try SwiftDriverExecutor(diagnosticsEngine: DiagnosticsEngine(),
                                           processSet: ProcessSet(),
                                           fileSystem: localFileSystem,
                                           env: ProcessEnv.vars)
    #if os(macOS)
    toolchain = DarwinToolchain(env: ProcessEnv.vars, executor: executor)
    #elseif os(Windows)
    toolchain = WindowsToolchain(env: ProcessEnv.vars, executor: executor)
    #else
    toolchain = GenericUnixToolchain(env: ProcessEnv.vars, executor: executor)
    #endif

    XCTAssertEqual(
      try? toolchain.getToolPath(.swiftCompiler).parentDirectory,
      try? toolchain.getToolPath(.clang).parentDirectory
    )
  }

  func testExecutableFallbackPath() throws {
    let driver1 = try Driver(args: ["swift", "main.swift"])
    if !driver1.targetTriple.isDarwin {
      XCTAssertThrowsError(try driver1.toolchain.getToolPath(.dsymutil))
    }

    var env = ProcessEnv.vars
    env["SWIFT_DRIVER_TESTS_ENABLE_EXEC_PATH_FALLBACK"] = "1"
    let driver2 = try Driver(args: ["swift", "main.swift"], env: env)
    XCTAssertNoThrow(try driver2.toolchain.getToolPath(.dsymutil))
  }

  func testVersionRequest() throws {
    for arg in ["-version", "--version"] {
      var driver = try Driver(args: ["swift"] + [arg])
      let plannedJobs = try driver.planBuild()
      XCTAssertTrue(plannedJobs.count == 1)
      let job = plannedJobs[0]
      XCTAssertEqual(job.kind, .versionRequest)
      XCTAssertEqual(job.commandLine, [.flag("--version")])
    }
  }

  func testNoInputs() throws {
    // A plain `swift` invocation requires lldb to be present
    if try testEnvHasLLDB() {
      do {
        var driver = try Driver(args: ["swift"], env: envWithFakeSwiftHelp)
        XCTAssertNoThrow(try driver.planBuild())
      }
    }
    do {
      var driver = try Driver(args: ["swiftc"], env: envWithFakeSwiftHelp)
      XCTAssertThrowsError(try driver.planBuild()) {
        XCTAssertEqual($0 as? Driver.Error, .noInputFiles)
      }
    }
    do {
      var driver = try Driver(args: ["swiftc", "-v"])
      XCTAssertNoThrow(try driver.planBuild())
    }
    do {
      var driver = try Driver(args: ["swiftc", "-v", "-whole-module-optimization"])
      XCTAssertNoThrow(try driver.planBuild())
    }
    do {
      var driver = try Driver(args: ["swiftc", "-whole-module-optimization"])
      XCTAssertThrowsError(try driver.planBuild()) {
        XCTAssertEqual($0 as? Driver.Error, .noInputFiles)
      }
    }
  }

  func testPrintTargetInfo() throws {
    do {
      var driver = try Driver(args: ["swift", "-print-target-info", "-target", "arm64-apple-ios12.0", "-sdk", "bar", "-resource-dir", "baz"])
      let plannedJobs = try driver.planBuild()
      XCTAssertTrue(plannedJobs.count == 1)
      let job = plannedJobs[0]
      XCTAssertEqual(job.kind, .printTargetInfo)
      XCTAssertTrue(job.commandLine.contains(.flag("-print-target-info")))
      XCTAssertTrue(job.commandLine.contains(.flag("-target")))
      XCTAssertTrue(job.commandLine.contains(.flag("-sdk")))
      XCTAssertTrue(job.commandLine.contains(.flag("-resource-dir")))
    }

    // In-process query
    do {
      let targetInfoArgs = ["-print-target-info", "-sdk", "/bar", "-resource-dir", "baz"]
      let driver = try Driver(args: ["swift"] + targetInfoArgs)
      let printTargetInfoJob = try driver.toolchain.printTargetInfoJob(target: nil, targetVariant: nil,
                                                                       sdkPath: .absolute(driver.absoluteSDKPath!),
                                                                       swiftCompilerPrefixArgs: [])
      var printTargetInfoCommand = try Driver.itemizedJobCommand(of: printTargetInfoJob, useResponseFiles: .disabled, using: ArgsResolver(fileSystem: InMemoryFileSystem()))
      Driver.sanitizeCommandForLibScanInvocation(&printTargetInfoCommand)
      let swiftScanLibPath = try XCTUnwrap(driver.getSwiftScanLibPath())
      if localFileSystem.exists(swiftScanLibPath) {
        let libSwiftScanInstance = try SwiftScan(dylib: swiftScanLibPath)
        if libSwiftScanInstance.canQueryTargetInfo() {
          XCTAssertTrue(try driver.verifyBeingAbleToQueryTargetInfoInProcess(workingDirectory: localFileSystem.currentWorkingDirectory,
                                                                             invocationCommand: printTargetInfoCommand,
                                                                             expectedSDKPath: "/bar"))
        }
      }
    }

    // Ensure that quoted paths are always escaped on the in-process query commands
    do {
      let targetInfoArgs = ["-print-target-info", "-sdk", "/tmp/foo bar", "-resource-dir", "baz"]
      let driver = try Driver(args: ["swift"] + targetInfoArgs)
      let printTargetInfoJob = try driver.toolchain.printTargetInfoJob(target: nil, targetVariant: nil,
                                                                       sdkPath: .absolute(driver.absoluteSDKPath!),
                                                                       swiftCompilerPrefixArgs: [])
      var printTargetInfoCommand = try Driver.itemizedJobCommand(of: printTargetInfoJob, useResponseFiles: .disabled, using: ArgsResolver(fileSystem: InMemoryFileSystem()))
      Driver.sanitizeCommandForLibScanInvocation(&printTargetInfoCommand)
      let swiftScanLibPath = try XCTUnwrap(driver.getSwiftScanLibPath())
      if localFileSystem.exists(swiftScanLibPath) {
        let libSwiftScanInstance = try SwiftScan(dylib: swiftScanLibPath)
        if libSwiftScanInstance.canQueryTargetInfo() {
          XCTAssertTrue(try driver.verifyBeingAbleToQueryTargetInfoInProcess(workingDirectory: localFileSystem.currentWorkingDirectory,
                                                                             invocationCommand: printTargetInfoCommand,
                                                                             expectedSDKPath: "/tmp/foo bar"))
        }
      }
    }

    do {
      struct MockExecutor: DriverExecutor {
        let resolver: ArgsResolver

        func execute(job: Job, forceResponseFiles: Bool, recordedInputModificationDates: [TypedVirtualPath : TimePoint]) throws -> ProcessResult {
          return ProcessResult(arguments: [], environment: [:], exitStatus: .terminated(code: 0), output: .success(Array("bad JSON".utf8)), stderrOutput: .success([]))
        }
        func execute(workload: DriverExecutorWorkload,
                     delegate: JobExecutionDelegate,
                     numParallelJobs: Int,
                     forceResponseFiles: Bool,
                     recordedInputModificationDates: [TypedVirtualPath : TimePoint]) throws {
          fatalError()
        }
        func checkNonZeroExit(args: String..., environment: [String : String]) throws -> String {
          return try Process.checkNonZeroExit(arguments: args, environment: environment)
        }
        func description(of job: Job, forceResponseFiles: Bool) throws -> String {
          fatalError()
        }
      }

      // Override path to libSwiftScan to force the fallback of using the executor
      var hideSwiftScanEnv = ProcessEnv.vars
      hideSwiftScanEnv["SWIFT_DRIVER_SWIFTSCAN_LIB"] = "/bad/path/lib_InternalSwiftScan.dylib"
      XCTAssertThrowsError(try Driver(args: ["swift", "-print-target-info"],
                                      env: hideSwiftScanEnv,
                                      executor: MockExecutor(resolver: ArgsResolver(fileSystem: InMemoryFileSystem())))) {
        error in
        if case .unableToDecodeFrontendTargetInfo = error as? Driver.Error {}
        else {
          XCTFail("not a decoding error")
        }
      }
    }

    do {
      XCTAssertThrowsError(try Driver(args: ["swift", "-print-target-info"],
                                      env: ["SWIFT_DRIVER_SWIFT_FRONTEND_EXEC": "/bad/path/to/swift-frontend"])) {
        error in
        XCTAssertTrue(error is Driver.Error)

        switch error {
        case Driver.Error.failedToRetrieveFrontendTargetInfo,
             Driver.Error.failedToRunFrontendToRetrieveTargetInfo:
          break;

        default:
          XCTFail("unexpected error \(error)")
        }
      }
    }

    do {
      var driver = try Driver(args: ["swift", "-print-target-info", "-target", "x86_64-apple-ios13.1-macabi", "-target-variant", "x86_64-apple-macosx10.14", "-sdk", "bar", "-resource-dir", "baz"])
      let plannedJobs = try driver.planBuild()
      XCTAssertTrue(plannedJobs.count == 1)
      let job = plannedJobs[0]
      XCTAssertEqual(job.kind, .printTargetInfo)
      XCTAssertTrue(job.commandLine.contains(.flag("-print-target-info")))
      XCTAssertTrue(job.commandLine.contains(.flag("-target")))
      XCTAssertTrue(job.commandLine.contains(.flag("-target-variant")))
      XCTAssertTrue(job.commandLine.contains(.flag("-sdk")))
      XCTAssertTrue(job.commandLine.contains(.flag("-resource-dir")))
    }

    do {
      var driver = try Driver(args: ["swift", "-print-target-info", "-target", "x86_64-unknown-linux"])
      let plannedJobs = try driver.planBuild()
      XCTAssertTrue(plannedJobs.count == 1)
      let job = plannedJobs[0]
      XCTAssertEqual(job.kind, .printTargetInfo)
      XCTAssertTrue(job.commandLine.contains(.flag("-print-target-info")))
      XCTAssertTrue(job.commandLine.contains(.flag("-target")))
      XCTAssertFalse(job.commandLine.contains(.flag("-use-static-resource-dir")))
    }

    do {
      var driver = try Driver(args: ["swift", "-print-target-info", "-target", "x86_64-unknown-linux", "-static-stdlib"])
      let plannedJobs = try driver.planBuild()
      XCTAssertTrue(plannedJobs.count == 1)
      let job = plannedJobs[0]
      XCTAssertEqual(job.kind, .printTargetInfo)
      XCTAssertTrue(job.commandLine.contains(.flag("-print-target-info")))
      XCTAssertTrue(job.commandLine.contains(.flag("-target")))
      XCTAssertTrue(job.commandLine.contains(.flag("-use-static-resource-dir")))
    }

    do {
      var driver = try Driver(args: ["swift", "-print-target-info", "-target", "x86_64-unknown-linux", "-static-executable"])
      let plannedJobs = try driver.planBuild()
      XCTAssertTrue(plannedJobs.count == 1)
      let job = plannedJobs[0]
      XCTAssertEqual(job.kind, .printTargetInfo)
      XCTAssertTrue(job.commandLine.contains(.flag("-print-target-info")))
      XCTAssertTrue(job.commandLine.contains(.flag("-target")))
      XCTAssertTrue(job.commandLine.contains(.flag("-use-static-resource-dir")))
    }
  }

  func testFrontendSupportedArguments() throws {
    do {
      // General case: ensure supported frontend arguments have been computed, one way or another
      let driver = try Driver(args: ["swift", "-target", "arm64-apple-ios12.0",
                                     "-resource-dir", "baz"])
      XCTAssertTrue(driver.supportedFrontendFlags.contains("emit-module"))
    }
    do {
      let driver = try Driver(args: ["swift", "-target", "arm64-apple-ios12.0",
                                     "-resource-dir", "baz"])
      if let libraryBasedResult = try driver.querySupportedArgumentsForTest() {
        XCTAssertTrue(libraryBasedResult.contains("emit-module"))
      }
    }
    do {
      // Test the fallback path of computing the supported arguments using a swift-frontend
      // invocation, by pointing the driver to look for libSwiftScan in a place that does not
      // exist
      var env = ProcessEnv.vars
      env["SWIFT_DRIVER_SWIFT_SCAN_TOOLCHAIN_PATH"] = "/some/nonexistent/path"
      let driver = try Driver(args: ["swift", "-target", "arm64-apple-ios12.0",
                                     "-resource-dir", "baz"],
                              env: env)
      XCTAssertTrue(driver.supportedFrontendFlags.contains("emit-module"))
    }
  }

  func testPrintOutputFileMap() throws {
    try withTemporaryDirectory { path in
      // Replace the error stream with one we capture here.
      let errorStream = stderrStream

      let root = localFileSystem.currentWorkingDirectory!.appending(components: "build")

      let errorOutputFile = path.appending(component: "dummy_error_stream")
      TSCBasic.stderrStream = try ThreadSafeOutputByteStream(LocalFileOutputByteStream(errorOutputFile))

      let libObj: AbsolutePath = root.appending(component: "lib.o")
      let mainObj: AbsolutePath = root.appending(component: "main.o")
      let basicOutputFileMapObj: AbsolutePath = root.appending(component: "basic_output_file_map.o")

      let dummyInput: AbsolutePath = path.appending(component: "output_file_map_test.swift")
      let mainSwift: AbsolutePath = path.appending(components: "Inputs", "main.swift")
      let libSwift: AbsolutePath = path.appending(components: "Inputs", "lib.swift")
      let outputFileMap = path.appending(component: "output_file_map.json")

      let fileMap = ByteString("""
        {
            \"\(dummyInput.nativePathString(escaped: true))\": {
                \"object\": \"\(basicOutputFileMapObj.nativePathString(escaped: true))\"
            },
            \"\(mainSwift.nativePathString(escaped: true))\": {
                \"object\": \"\(mainObj.nativePathString(escaped: true))\"
            },
            \"\(libSwift.nativePathString(escaped: true))\": {
                \"object\": \"\(libObj.nativePathString(escaped: true))\"
            }
        }
        """.utf8)
      try localFileSystem.writeFileContents(outputFileMap, bytes: fileMap)

      var driver = try Driver(args: ["swiftc", "-driver-print-output-file-map",
                                     "-target", "x86_64-apple-macosx10.9",
                                     "-o", root.appending(component: "basic_output_file_map.out").nativePathString(escaped: false),
                                     "-module-name", "OutputFileMap",
                                     "-output-file-map", outputFileMap.nativePathString(escaped: false)])
      try driver.run(jobs: [])
      let invocationError = try localFileSystem.readFileContents(errorOutputFile).description

      XCTAssertTrue(invocationError.contains("\(libSwift.nativePathString(escaped: false)) -> object: \"\(libObj.nativePathString(escaped: false))\""))
      XCTAssertTrue(invocationError.contains("\(mainSwift.nativePathString(escaped: false)) -> object: \"\(mainObj.nativePathString(escaped: false))\""))
      XCTAssertTrue(invocationError.contains("\(dummyInput.nativePathString(escaped: false)) -> object: \"\(basicOutputFileMapObj.nativePathString(escaped: false))\""))

      // Restore the error stream to what it was
      TSCBasic.stderrStream = errorStream
    }
  }

  func testVerboseImmediateMode() throws {
    #if os(macOS) && arch(arm64)
      try XCTSkipIf(true, "Temporarily disabled on Apple Silicon (rdar://80558898)")
    #endif

// There is nothing particularly macOS-specific about this test other than
// the use of some macOS-specific XCTest functionality to determine the
// test bundle that contains the swift-driver executable.
#if os(macOS)
    try withTemporaryDirectory { path in
      let input = path.appending(component: "ImmediateTest.swift")
      try localFileSystem.writeFileContents(input, bytes: "print(\"Hello, World\")")
      let binDir = try bundleRoot()
      let driver = binDir.appending(component: "swift-driver")
      let args = [driver.description, "--driver-mode=swift", "-v", input.description]
      // Immediate mode takes over the process with `exec` so we need to create
      // a separate process to capture its output here
      let result = try TSCBasic.Process.checkNonZeroExit(
        arguments: args,
        environment: ProcessEnv.vars
      )
      // Make sure the interpret job description was printed
      XCTAssertTrue(result.contains("-frontend -interpret \(input.description)"))
      XCTAssertTrue(result.contains("Hello, World"))
    }
#endif
  }

  func testDiagnosticOptions() throws {
    do {
      var driver = try Driver(args: ["swift", "-no-warnings-as-errors", "-warnings-as-errors", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      let job = plannedJobs[0]
      XCTAssertTrue(job.commandLine.contains(.flag("-warnings-as-errors")))
    }

    do {
      var driver = try Driver(args: ["swift", "-warnings-as-errors", "-no-warnings-as-errors", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      let job = plannedJobs[0]
      XCTAssertTrue(job.commandLine.contains(.flag("-no-warnings-as-errors")))
    }

    do {
      var driver = try Driver(args: ["swift", "-warnings-as-errors", "-no-warnings-as-errors", "-suppress-warnings", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      let job = plannedJobs[0]
      XCTAssertTrue(job.commandLine.contains(.flag("-no-warnings-as-errors")))
      XCTAssertTrue(job.commandLine.contains(.flag("-suppress-warnings")))
    }

    do {
      try assertDriverDiagnostics(args: ["swift", "-no-warnings-as-errors", "-warnings-as-errors", "-suppress-warnings", "foo.swift"]) {
        $1.expect(.error(Driver.Error.conflictingOptions(.warningsAsErrors, .suppressWarnings)))
      }
    }

    do {
      var driver = try Driver(args: ["swift", "-print-educational-notes", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      let job = plannedJobs[0]
      XCTAssertTrue(job.commandLine.contains(.flag("-print-educational-notes")))
    }
  }

  func testNumThreads() throws {
    XCTAssertEqual(try Driver(args: ["swiftc"]).numThreads, 0)

    XCTAssertEqual(try Driver(args: ["swiftc", "-num-threads", "4"]).numThreads, 4)

    XCTAssertEqual(try Driver(args: ["swiftc", "-num-threads", "0"]).numThreads, 0)

    try assertDriverDiagnostics(args: ["swift", "-num-threads", "-1"]) { driver, verify in
      verify.expect(.error("invalid value '-1' in '-num-threads'"))
      XCTAssertEqual(driver.numThreads, 0)
    }

    try assertDriverDiagnostics(args: "swiftc", "-enable-batch-mode", "-num-threads", "4") { driver, verify in
      verify.expect(.warning("ignoring -num-threads argument; cannot multithread batch mode"))
      XCTAssertEqual(driver.numThreads, 0)
    }
  }

  func testLTOOption() throws {
    XCTAssertEqual(try Driver(args: ["swiftc"]).lto, nil)

    XCTAssertEqual(try Driver(args: ["swiftc", "-lto=llvm-thin"]).lto, .llvmThin)

    XCTAssertEqual(try Driver(args: ["swiftc", "-lto=llvm-full"]).lto, .llvmFull)

    try assertDriverDiagnostics(args: ["swiftc", "-lto=nop"]) { driver, verify in
      verify.expect(.error("invalid value 'nop' in '-lto=', valid options are: llvm-thin, llvm-full"))
    }
  }

  func testLTOOutputs() throws {
    var envVars = ProcessEnv.vars
    envVars["SWIFT_DRIVER_LD_EXEC"] = ld.nativePathString(escaped: false)

    let targets = ["x86_64-unknown-linux-gnu", "x86_64-apple-macosx10.9"]
    for target in targets {
      var driver = try Driver(args: ["swiftc", "foo.swift", "-lto=llvm-thin", "-target", target],
                              env: envVars)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 2)
      XCTAssertTrue(plannedJobs[0].commandLine.contains(.flag("-emit-bc")))
      XCTAssertTrue(matchTemporary(plannedJobs[0].outputs.first!.file, "foo.bc"))
      XCTAssertTrue(matchTemporary(plannedJobs[1].inputs.first!.file, "foo.bc"))
    }
  }

  func testLTOLibraryArg() throws {
    #if os(macOS)
    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "-lto=llvm-thin", "-target", "x86_64-apple-macos11.0"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.map(\.kind), [.compile, .link])
      XCTAssertTrue(plannedJobs[1].commandLine.contains("-flto=thin"))
    }

    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "-lto=llvm-thin", "-lto-library", "/foo/libLTO.dylib", "-target", "x86_64-apple-macos11.0"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.map(\.kind), [.compile, .link])
      XCTAssertFalse(plannedJobs[0].commandLine.contains(.path(try VirtualPath(path: "/foo/libLTO.dylib"))))
      XCTAssertTrue(plannedJobs[1].commandLine.contains("-flto=thin"))
      XCTAssertTrue(plannedJobs[1].commandLine.contains(.joinedOptionAndPath("-Wl,-lto_library,", try VirtualPath(path: "/foo/libLTO.dylib"))))
    }

    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "-lto=llvm-full", "-target", "x86_64-apple-macos11.0"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.map(\.kind), [.compile, .link])
      XCTAssertTrue(plannedJobs[1].commandLine.contains("-flto=full"))
    }

    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "-lto=llvm-full", "-lto-library", "/foo/libLTO.dylib", "-target", "x86_64-apple-macos11.0"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.map(\.kind), [.compile, .link])
      XCTAssertFalse(plannedJobs[0].commandLine.contains(.path(try VirtualPath(path: "/foo/libLTO.dylib"))))
      XCTAssertTrue(plannedJobs[1].commandLine.contains("-flto=full"))
      XCTAssertTrue(plannedJobs[1].commandLine.contains(.joinedOptionAndPath("-Wl,-lto_library,", try VirtualPath(path: "/foo/libLTO.dylib"))))
    }

    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "-target", "x86_64-apple-macos11.0"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.map(\.kind), [.compile, .link])
      XCTAssertFalse(plannedJobs[1].commandLine.contains("-flto=thin"))
      XCTAssertFalse(plannedJobs[1].commandLine.contains("-flto=full"))
    }
    #endif
  }

  func testBCasTopLevelOutput() throws {
    var driver = try Driver(args: ["swiftc", "foo.swift", "-emit-bc", "-target", "x86_64-apple-macosx10.9"])
    let plannedJobs = try driver.planBuild()
    XCTAssertEqual(plannedJobs.count, 1)
    XCTAssertTrue(plannedJobs[0].commandLine.contains(.flag("-emit-bc")))
    XCTAssertEqual(plannedJobs[0].outputs.first!.file, try toPath("foo.bc"))
  }

  func testScanDependenciesOption() throws {
    do {
      var driver = try Driver(args: ["swiftc", "-scan-dependencies", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      let job = plannedJobs[0]
      XCTAssertTrue(job.commandLine.contains(.flag("-scan-dependencies")))
    }

    // Test .d output
    do {
      var driver = try Driver(args: ["swiftc", "-scan-dependencies",
                                     "-emit-dependencies", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      let job = plannedJobs[0]
      XCTAssertTrue(job.commandLine.contains(.flag("-scan-dependencies")))
      XCTAssertTrue(job.commandLine.contains(.flag("-emit-dependencies-path")))
      XCTAssertTrue(commandContainsTemporaryPath(job.commandLine, "foo.d"))
    }
  }

  func testUserModuleVersion() throws {
    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-module-name",
                                     "foo", "-user-module-version", "12.21"])
      guard driver.isFrontendArgSupported(.userModuleVersion) else {
        throw XCTSkip("Skipping: compiler does not support '-user-module-version'")
      }
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 2)
      let emitModuleJob = plannedJobs[0]
      XCTAssertEqual(emitModuleJob.kind, .emitModule)
      XCTAssertTrue(emitModuleJob.commandLine.contains(.flag("-user-module-version")))
      XCTAssertTrue(emitModuleJob.commandLine.contains(.flag("12.21")))
    }
  }

  func testExperimentalPerformanceAnnotations() throws {
    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "-experimental-performance-annotations",
                                     "-emit-sil", "-o", "foo.sil"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      let emitModuleJob = plannedJobs[0]
      XCTAssertEqual(emitModuleJob.kind, .compile)
      XCTAssertTrue(emitModuleJob.commandLine.contains(.flag("-experimental-performance-annotations")))
    }
  }

  func testVerifyEmittedInterfaceJob() throws {
    // Evolution enabled
    var envVars = ProcessEnv.vars
    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-module-name",
                                     "foo", "-emit-module-interface",
                                     "-emit-private-module-interface-path", "foo.private.swiftinterface",
                                     "-verify-emitted-module-interface",
                                     "-enable-library-evolution"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 4)

      // Emit-module should emit both module interface files
      let emitJob = try plannedJobs.findJob(.emitModule)
      let publicModuleInterface = emitJob.outputs.filter { $0.type == .swiftInterface }
      XCTAssertEqual(publicModuleInterface.count, 1)
      let privateModuleInterface = emitJob.outputs.filter { $0.type == .privateSwiftInterface }
      XCTAssertEqual(privateModuleInterface.count, 1)

      // Each verify job should either check the public or the private module interface, not both.
      let verifyJobs = plannedJobs.filter { $0.kind == .verifyModuleInterface }
      XCTAssertEqual(verifyJobs.count, 2)
      for verifyJob in verifyJobs {
        let publicVerify = verifyJob.inputs.contains(try XCTUnwrap(publicModuleInterface.first))
        let privateVerify = verifyJob.inputs.contains(try XCTUnwrap(privateModuleInterface.first))
        XCTAssertNotEqual(publicVerify, privateVerify)
        XCTAssertFalse(verifyJob.commandLine.contains("-downgrade-typecheck-interface-error"))
      }
    }

    // No Evolution
    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-module-name",
                                     "foo", "-emit-module-interface", "-verify-emitted-module-interface"], env: envVars)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 2)
      XCTAssertFalse(plannedJobs.containsJob(.verifyModuleInterface))
    }

    // Explicitly disabled
    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-module-name",
                                     "foo", "-emit-module-interface",
                                     "-enable-library-evolution",
                                     "-no-verify-emitted-module-interface"], env: envVars)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 2)
      XCTAssertFalse(plannedJobs.containsJob(.verifyModuleInterface))
      let emitJob = try plannedJobs.findJob(.emitModule)
      if driver.isFrontendArgSupported(.noVerifyEmittedModuleInterface) {
        XCTAssertTrue(emitJob.commandLine.contains("-no-verify-emitted-module-interface"))
      }
    }

    // Disabled by default in merge-module
    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-module-name",
                                     "foo", "-emit-module-interface",
                                     "-enable-library-evolution",
                                     "-no-emit-module-separately"], env: envVars)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 2)
      XCTAssertFalse(plannedJobs.containsJob(.verifyModuleInterface))
    }

    // Emit-module separately
    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-module-name",
                                     "foo", "-emit-module-interface",
                                     "-enable-library-evolution",
                                     "-experimental-emit-module-separately"], env: envVars)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)
      let emitJob = try plannedJobs.findJob(.emitModule)
      let verifyJob = try plannedJobs.findJob(.verifyModuleInterface)
      let emitInterfaceOutput = emitJob.outputs.filter { $0.type == .swiftInterface }
      XCTAssertTrue(emitInterfaceOutput.count == 1,
                    "Emit module job should only have one swiftinterface output")
      XCTAssertTrue(verifyJob.inputs.count == 1)
      XCTAssertTrue(verifyJob.inputs[0] == emitInterfaceOutput[0])
      XCTAssertTrue(verifyJob.commandLine.contains(.path(emitInterfaceOutput[0].file)))
      XCTAssertFalse(verifyJob.commandLine.contains("-downgrade-typecheck-interface-error"))
      XCTAssertFalse(emitJob.commandLine.contains("-no-verify-emitted-module-interface"))
      XCTAssertFalse(emitJob.commandLine.contains("-verify-emitted-module-interface"))
    }

    // Whole-module
    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-module-name",
                                     "foo", "-emit-module-interface",
                                     "-enable-library-evolution",
                                     "-whole-module-optimization"], env: envVars)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 2)
      let emitJob = plannedJobs[0]
      let verifyJob = plannedJobs[1]
      XCTAssertEqual(emitJob.kind, .compile)
      let emitInterfaceOutput = emitJob.outputs.filter { $0.type == .swiftInterface }
      XCTAssertTrue(emitInterfaceOutput.count == 1,
                    "Emit module job should only have one swiftinterface output")
      XCTAssertEqual(verifyJob.kind, .verifyModuleInterface)
      XCTAssertTrue(verifyJob.inputs.count == 1)
      XCTAssertTrue(verifyJob.inputs[0] == emitInterfaceOutput[0])
      XCTAssertTrue(verifyJob.commandLine.contains(.path(emitInterfaceOutput[0].file)))
      XCTAssertFalse(verifyJob.commandLine.contains("-downgrade-typecheck-interface-error"))
    }

    // Test the `-no-verify-emitted-module-interface` flag with whole-module
    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-module-name",
                                     "foo", "-emit-module-interface",
                                     "-enable-library-evolution",
                                     "-whole-module-optimization",
                                     "-no-verify-emitted-module-interface"], env: envVars)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      let compileJob = try plannedJobs.findJob(.compile)
      if driver.isFrontendArgSupported(.noVerifyEmittedModuleInterface) {
        XCTAssertTrue(compileJob.commandLine.contains("-no-verify-emitted-module-interface"))
      }
    }

    // Enabled by default when the library-level is api.
    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-module-name",
                                     "foo", "-emit-module-interface",
                                     "-enable-library-evolution",
                                     "-whole-module-optimization",
                                     "-library-level", "api"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 2)
      let verifyJob = try plannedJobs.findJob(.verifyModuleInterface)
      XCTAssertFalse(verifyJob.commandLine.contains("-downgrade-typecheck-interface-error"))
    }

    // Enabled by default when the library-level is spi.
    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-module-name",
                                     "foo", "-emit-module-interface",
                                     "-enable-library-evolution",
                                     "-whole-module-optimization",
                                     "-library-level", "spi"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 2)
      let verifyJob = try plannedJobs.findJob(.verifyModuleInterface)
      XCTAssertFalse(verifyJob.commandLine.contains("-downgrade-typecheck-interface-error"))
    }

    // Errors downgraded to a warning when a module is blocklisted.
    try assertDriverDiagnostics(args: ["swiftc", "foo.swift", "-emit-module", "-module-name",
                                       "TestBlocklistedModule", "-emit-module-interface",
                                       "-enable-library-evolution",
                                       "-whole-module-optimization",
                                       "-library-level", "api"]) { driver, verify in
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 2)
      let verifyJob = try plannedJobs.findJob(.verifyModuleInterface)
      if driver.isFrontendArgSupported(.downgradeTypecheckInterfaceError) {
        XCTAssertTrue(verifyJob.commandLine.contains("-downgrade-typecheck-interface-error"))
      }

      verify.expect(.remark("Verification of module interfaces for 'TestBlocklistedModule' set to warning only by blocklist"))
    }

    // Don't downgrade to error blocklisted modules when the env var is set.
    do {
      envVars["ENABLE_DEFAULT_INTERFACE_VERIFIER"] = "YES"
      var driver = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-module-name",
                                     "TestBlocklistedModule", "-emit-module-interface",
                                     "-enable-library-evolution",
                                     "-whole-module-optimization"], env: envVars)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 2)
      let verifyJob = try plannedJobs.findJob(.verifyModuleInterface)
      XCTAssertFalse(verifyJob.commandLine.contains("-downgrade-typecheck-interface-error"))
    }

    // Don't downgrade to error blocklisted modules if the verify flag is set.
    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-module-name",
                                     "TestBlocklistedModule", "-emit-module-interface",
                                     "-enable-library-evolution",
                                     "-whole-module-optimization",
                                     "-verify-emitted-module-interface"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 2)
      let verifyJob = try plannedJobs.findJob(.verifyModuleInterface)
      XCTAssertFalse(verifyJob.commandLine.contains("-downgrade-typecheck-interface-error"))
    }

    // The flag -check-api-availability-only is not passed down to the verify job.
    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-module-name",
                                     "foo", "-emit-module-interface",
                                     "-verify-emitted-module-interface",
                                     "-enable-library-evolution",
                                     "-check-api-availability-only"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)

      let emitJob = try plannedJobs.findJob(.emitModule)
      XCTAssertTrue(emitJob.commandLine.contains(.flag("-check-api-availability-only")))

      let verifyJob = try plannedJobs.findJob(.verifyModuleInterface)
      XCTAssertFalse(verifyJob.commandLine.contains(.flag("-check-api-availability-only")))
    }

    // Do verify modules with compatibility headers.
    do {
      var driver = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-module-name",
                                     "foo", "-emit-module-interface",
                                     "-enable-library-evolution", "-emit-objc-header-path", "foo-Swift.h"],
                              env: envVars)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.filter( { job in job.kind == .verifyModuleInterface}).count, 1)
    }
  }

  func testVerifyEmittedPackageInterface() throws {
      // Evolution enabled
      do {
        var driver = try Driver(args: ["swiftc", "foo.swift", "-emit-module",
                                       "-module-name", "foo",
                                       "-package-name", "foopkg",
                                       "-emit-module-interface",
                                       "-emit-package-module-interface-path", "foo.package.swiftinterface",
                                       "-verify-emitted-module-interface",
                                       "-enable-library-evolution"])

        let plannedJobs = try driver.planBuild()
        XCTAssertEqual(plannedJobs.count, 4)
        let emitJob = try plannedJobs.findJob(.emitModule)
        let verifyJob = try plannedJobs.findJob(.verifyModuleInterface)
        let packageOutputs = emitJob.outputs.filter { $0.type == .packageSwiftInterface }
        let publicOutputs = emitJob.outputs.filter { $0.type == .swiftInterface }
        XCTAssertTrue(packageOutputs.count == 1,
                      "There should be one package swiftinterface output")
        XCTAssertTrue(publicOutputs.count == 1,
                      "There should be one public swiftinterface output")
        XCTAssertTrue(verifyJob.inputs.count == 1)
        XCTAssertTrue(verifyJob.inputs[0] == publicOutputs[0])
        XCTAssertTrue(verifyJob.outputs.isEmpty)
      }

      // Explicitly disabled
      do {
        var driver = try Driver(args: ["swiftc", "foo.swift", "-emit-module",
                                       "-module-name",  "foo",
                                       "-package-name", "foopkg",
                                       "-emit-module-interface",
                                       "-emit-package-module-interface-path", "foo.package.swiftinterface",
                                       "-enable-library-evolution",
                                       "-no-verify-emitted-module-interface"])
        let plannedJobs = try driver.planBuild()
        XCTAssertEqual(plannedJobs.count, 2)
      }

      // Emit-module separately
      do {
        var driver = try Driver(args: ["swiftc", "foo.swift", "-emit-module",
                                       "-module-name",  "foo",
                                       "-package-name", "foopkg",
                                       "-emit-module-interface",
                                       "-emit-package-module-interface-path", "foo.package.swiftinterface",
                                       "-enable-library-evolution",
                                       "-experimental-emit-module-separately"])
        let plannedJobs = try driver.planBuild()
        XCTAssertEqual(plannedJobs.count, 4)
        let emitJob = try plannedJobs.findJob(.emitModule)
        let verifyJob = try plannedJobs.findJob(.verifyModuleInterface)
        let packageOutputs = emitJob.outputs.filter { $0.type == .packageSwiftInterface }
        let publicOutputs = emitJob.outputs.filter { $0.type == .swiftInterface }
        XCTAssertTrue(packageOutputs.count == 1,
                      "There should be one package swiftinterface output")
        XCTAssertTrue(publicOutputs.count == 1,
                      "There should be one public swiftinterface output")
        XCTAssertTrue(verifyJob.inputs.count == 1)
        XCTAssertTrue(verifyJob.inputs[0] == publicOutputs[0])
        XCTAssertTrue(verifyJob.outputs.isEmpty)
      }
  }

  func testLoadPackageInterface() throws {
    try withTemporaryDirectory { path in
      let envVars = ProcessEnv.vars
      let main = path.appending(component: "main.swift")
      try localFileSystem.writeFileContents(main) {
        $0.send("import Foo;")
      }
      let swiftModuleInterfacesPath: AbsolutePath =
      try testInputsPath.appending(component: "testLoadPackageInterface")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try Driver(args: ["swiftc", main.nativePathString(escaped: true),
                                     "-typecheck", "-v",
                                     "-package-name", "foopkg",
                                     "-experimental-package-interface-load",
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                     "-enable-library-evolution"] + sdkArgumentsForTesting,
                              env: envVars)

      let plannedJobs = try driver.planBuild()
      XCTAssertTrue(plannedJobs.count == 1)
      XCTAssertTrue(plannedJobs[0].commandLine.contains(.flag("-experimental-package-interface-load")))
    }
  }

  func testPCHGeneration() throws {
    do {
      var driver = try Driver(args: ["swiftc", "-typecheck", "-import-objc-header", "TestInputHeader.h", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 2)

      XCTAssertEqual(plannedJobs[0].kind, .generatePCH)
      XCTAssertEqual(plannedJobs[0].inputs.count, 1)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, try toPath("TestInputHeader.h"))
      XCTAssertEqual(plannedJobs[0].inputs[0].type, .objcHeader)
      XCTAssertEqual(plannedJobs[0].outputs.count, 1)
      XCTAssertTrue(matchTemporary(plannedJobs[0].outputs[0].file, "TestInputHeader.pch"))
      XCTAssertEqual(plannedJobs[0].outputs[0].type, .pch)
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-frontend")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-emit-pch")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-o")))
      XCTAssertTrue(commandContainsTemporaryPath(plannedJobs[0].commandLine, "TestInputHeader.pch"))

      XCTAssertEqual(plannedJobs[1].kind, .compile)
      XCTAssertEqual(plannedJobs[1].inputs.count, 2)
      XCTAssertEqual(plannedJobs[1].inputs[0].file, try toPath("foo.swift"))
      XCTAssert(plannedJobs[1].commandLine.contains(.flag("-import-objc-header")))
      XCTAssertTrue(commandContainsTemporaryPath(plannedJobs[1].commandLine, "TestInputHeader.pch"))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-typecheck", "-disable-bridging-pch", "-import-objc-header", "TestInputHeader.h", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)

      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertEqual(plannedJobs[0].inputs.count, 1)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, try toPath("foo.swift"))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-import-objc-header")))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-typecheck", "-index-store-path", "idx", "-import-objc-header", "TestInputHeader.h", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 2)

      XCTAssertEqual(plannedJobs[0].kind, .generatePCH)
      XCTAssertEqual(plannedJobs[0].inputs.count, 1)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, try toPath("TestInputHeader.h"))
      XCTAssertEqual(plannedJobs[0].inputs[0].type, .objcHeader)
      XCTAssertEqual(plannedJobs[0].outputs.count, 1)
      XCTAssertTrue(matchTemporary(plannedJobs[0].outputs[0].file, "TestInputHeader.pch"))
      XCTAssertEqual(plannedJobs[0].outputs[0].type, .pch)
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-frontend")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-emit-pch")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-index-store-path")))
      XCTAssert(plannedJobs[0].commandLine.contains(.path(try toPath("idx"))))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-o")))
      XCTAssertTrue(commandContainsTemporaryPath(plannedJobs[0].commandLine, "TestInputHeader.pch"))

      XCTAssertEqual(plannedJobs[1].kind, .compile)
      XCTAssertEqual(plannedJobs[1].inputs.count, 2)
      XCTAssertEqual(plannedJobs[1].inputs[0].file, try toPath("foo.swift"))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-typecheck", "-import-objc-header", "TestInputHeader.h", "-pch-output-dir", "/pch", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 2)

      XCTAssertEqual(plannedJobs[0].kind, .generatePCH)
      XCTAssertEqual(plannedJobs[0].inputs.count, 1)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, try toPath("TestInputHeader.h"))
      XCTAssertEqual(plannedJobs[0].inputs[0].type, .objcHeader)
      XCTAssertEqual(plannedJobs[0].outputs.count, 1)
      XCTAssertEqual(plannedJobs[0].outputs[0].file.nativePathString(escaped: false), try VirtualPath(path: "/pch/TestInputHeader.pch").nativePathString(escaped: false))
      XCTAssertEqual(plannedJobs[0].outputs[0].type, .pch)
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-frontend")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-emit-pch")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-pch-output-dir")))
      XCTAssert(plannedJobs[0].commandLine.contains(.path(try VirtualPath(path: "/pch"))))

      XCTAssertEqual(plannedJobs[1].kind, .compile)
      XCTAssertEqual(plannedJobs[1].inputs.count, 2)
      XCTAssertEqual(plannedJobs[1].inputs[0].file, try toPath("foo.swift"))
      XCTAssert(plannedJobs[1].commandLine.contains(.flag("-pch-disable-validation")))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-c", "-embed-bitcode", "-import-objc-header", "TestInputHeader.h", "-pch-output-dir", "/pch", "foo.swift"])
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(plannedJobs.count, 3)

      XCTAssertEqual(plannedJobs[0].kind, .generatePCH)
      XCTAssertEqual(plannedJobs[0].inputs.count, 1)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, try toPath("TestInputHeader.h"))
      XCTAssertEqual(plannedJobs[0].inputs[0].type, .objcHeader)
      XCTAssertEqual(plannedJobs[0].outputs.count, 1)
      XCTAssertEqual(plannedJobs[0].outputs[0].file.nativePathString(escaped: false), try VirtualPath(path: "/pch/TestInputHeader.pch").nativePathString(escaped: false))
      XCTAssertEqual(plannedJobs[0].outputs[0].type, .pch)
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-frontend")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-emit-pch")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-pch-output-dir")))
      XCTAssert(plannedJobs[0].commandLine.contains(.path(try VirtualPath(path: "/pch"))))

      XCTAssertEqual(plannedJobs[1].kind, .compile)
      XCTAssertEqual(plannedJobs[1].inputs.count, 2)
      XCTAssertEqual(plannedJobs[1].inputs[0].file, try toPath("foo.swift"))
      XCTAssertEqual(plannedJobs[1].outputs.count, 1)
      XCTAssertTrue(matchTemporary(plannedJobs[1].outputs[0].file, "foo.bc"))

      XCTAssertEqual(plannedJobs[2].kind, .backend)
    }

    do {
      var driver = try Driver(args: ["swiftc", "-typecheck", "-disable-bridging-pch", "-import-objc-header", "TestInputHeader.h", "-pch-output-dir", "/pch", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)

      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertEqual(plannedJobs[0].inputs.count, 1)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, try toPath("foo.swift"))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-import-objc-header")))
      XCTAssertFalse(plannedJobs[0].commandLine.contains(.flag("-pch-output-dir")))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-typecheck", "-disable-bridging-pch", "-import-objc-header", "TestInputHeader.h", "-pch-output-dir", "/pch", "-whole-module-optimization", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)

      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertEqual(plannedJobs[0].inputs.count, 1)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, try toPath("foo.swift"))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-import-objc-header")))
      XCTAssertFalse(plannedJobs[0].commandLine.contains(.flag("-pch-output-dir")))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-typecheck", "-import-objc-header", "TestInputHeader.h", "-pch-output-dir", "/pch", "-serialize-diagnostics", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 2)

      XCTAssertEqual(plannedJobs[0].kind, .generatePCH)
      XCTAssertEqual(plannedJobs[0].inputs.count, 1)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, try toPath("TestInputHeader.h"))
      XCTAssertEqual(plannedJobs[0].inputs[0].type, .objcHeader)
      XCTAssertEqual(plannedJobs[0].outputs.count, 2)
      XCTAssertTrue(matchTemporary(plannedJobs[0].outputs[0].file, "TestInputHeader.dia"))
      XCTAssertEqual(plannedJobs[0].outputs[0].type, .diagnostics)
      XCTAssertEqual(plannedJobs[0].outputs[1].file.nativePathString(escaped: false), try VirtualPath(path: "/pch/TestInputHeader.pch").nativePathString(escaped: false))
      XCTAssertEqual(plannedJobs[0].outputs[1].type, .pch)
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-serialize-diagnostics-path")))
      XCTAssertTrue(commandContainsTemporaryPath(plannedJobs[0].commandLine, "TestInputHeader.dia"))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-frontend")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-emit-pch")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-pch-output-dir")))
      XCTAssert(plannedJobs[0].commandLine.contains(.path(try VirtualPath(path: "/pch"))))

      XCTAssertEqual(plannedJobs[1].kind, .compile)
      XCTAssertEqual(plannedJobs[1].inputs.count, 2)
      XCTAssertEqual(plannedJobs[1].inputs[0].file, try toPath("foo.swift"))
      XCTAssert(plannedJobs[1].commandLine.contains(.flag("-pch-disable-validation")))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-typecheck", "-import-objc-header", "TestInputHeader.h", "-pch-output-dir", "/pch", "-serialize-diagnostics", "foo.swift", "-emit-module", "-emit-module-path", "/module-path-dir"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)

      XCTAssertEqual(plannedJobs[0].kind, .generatePCH)
      XCTAssertEqual(plannedJobs[0].inputs.count, 1)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, try toPath("TestInputHeader.h"))
      XCTAssertEqual(plannedJobs[0].inputs[0].type, .objcHeader)
      XCTAssertEqual(plannedJobs[0].outputs.count, 2)
      XCTAssertNotNil(plannedJobs[0].outputs[0].file.name.range(of: #"[\\/]pch[\\/]TestInputHeader-.*.dia"#, options: .regularExpression))
      XCTAssertEqual(plannedJobs[0].outputs[0].type, .diagnostics)
      XCTAssertEqual(plannedJobs[0].outputs[1].file.nativePathString(escaped: false), try VirtualPath(path: "/pch/TestInputHeader.pch").nativePathString(escaped: false))
      XCTAssertEqual(plannedJobs[0].outputs[1].type, .pch)
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-serialize-diagnostics-path")))
      XCTAssert(plannedJobs[0].commandLine.contains {
        guard case .path(let path) = $0 else { return false }
        return path.name.range(of: #"[\\/]pch[\\/]TestInputHeader-.*.dia"#, options: .regularExpression) != nil
      })
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-frontend")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-emit-pch")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-pch-output-dir")))
      XCTAssert(plannedJobs[0].commandLine.contains(.path(try VirtualPath(path: "/pch"))))

      XCTAssertEqual(plannedJobs[1].kind, .emitModule)
      XCTAssertEqual(plannedJobs[1].inputs.count, 2)
      XCTAssertEqual(plannedJobs[1].inputs[0].file, try toPath("foo.swift"))
      XCTAssert(plannedJobs[1].commandLine.contains(.flag("-pch-disable-validation")))

      // FIXME: validate that merge module is correct job and that it has correct inputs and flags
    }

    do {
      var driver = try Driver(args: ["swiftc", "-typecheck", "-import-objc-header", "TestInputHeader.h", "-pch-output-dir", "/pch", "-whole-module-optimization", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 2)

      XCTAssertEqual(plannedJobs[0].kind, .generatePCH)
      XCTAssertEqual(plannedJobs[0].inputs.count, 1)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, try toPath("TestInputHeader.h"))
      XCTAssertEqual(plannedJobs[0].inputs[0].type, .objcHeader)
      XCTAssertEqual(plannedJobs[0].outputs.count, 1)
      XCTAssertEqual(plannedJobs[0].outputs[0].file.nativePathString(escaped: false), try VirtualPath(path: "/pch/TestInputHeader.pch").nativePathString(escaped: false))
      XCTAssertEqual(plannedJobs[0].outputs[0].type, .pch)
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-frontend")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-emit-pch")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-pch-output-dir")))
      XCTAssert(plannedJobs[0].commandLine.contains(.path(try VirtualPath(path: "/pch"))))

      XCTAssertEqual(plannedJobs[1].kind, .compile)
      XCTAssertEqual(plannedJobs[1].inputs.count, 2)
      XCTAssertEqual(plannedJobs[1].inputs[0].file, try toPath("foo.swift"))
      XCTAssertFalse(plannedJobs[1].commandLine.contains(.flag("-pch-disable-validation")))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-typecheck", "-O", "-import-objc-header", "TestInputHeader.h", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 2)

      XCTAssertEqual(plannedJobs[0].kind, .generatePCH)
      XCTAssertEqual(plannedJobs[0].inputs.count, 1)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, try toPath("TestInputHeader.h"))
      XCTAssertEqual(plannedJobs[0].inputs[0].type, .objcHeader)
      XCTAssertEqual(plannedJobs[0].outputs.count, 1)
      XCTAssertTrue(matchTemporary(plannedJobs[0].outputs[0].file, "TestInputHeader.pch"))
      XCTAssertEqual(plannedJobs[0].outputs[0].type, .pch)
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-O")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-frontend")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-emit-pch")))
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-o")))
      XCTAssertTrue(commandContainsTemporaryPath(plannedJobs[0].commandLine, "TestInputHeader.pch"))

      XCTAssertEqual(plannedJobs[1].kind, .compile)
      XCTAssertEqual(plannedJobs[1].inputs.count, 2)
      XCTAssertEqual(plannedJobs[1].inputs[0].file, try toPath("foo.swift"))
    }

    // Ensure the merge-module step is not passed the precompiled header
    do {
      var driver = try Driver(args: ["swiftc", "-emit-module", "-import-objc-header", "header.h", "foo.swift", "-no-emit-module-separately"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)

      XCTAssertEqual(plannedJobs[0].kind, .generatePCH)
      XCTAssertEqual(plannedJobs[0].inputs.count, 1)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, try toPath("header.h"))
      XCTAssertEqual(plannedJobs[0].inputs[0].type, .objcHeader)
      XCTAssertEqual(plannedJobs[0].outputs.count, 1)
      XCTAssertTrue(matchTemporary(plannedJobs[0].outputs[0].file, "header.pch"))
      XCTAssertEqual(plannedJobs[0].outputs[0].type, .pch)
      XCTAssertTrue(plannedJobs[0].commandLine.contains(.flag("-emit-pch")))
      XCTAssertTrue(commandContainsFlagTemporaryPathSequence(plannedJobs[0].commandLine,
                                                             flag: "-o", filename: "header.pch"))

      XCTAssertEqual(plannedJobs[1].kind, .compile)
      XCTAssertTrue(commandContainsFlagTemporaryPathSequence(plannedJobs[1].commandLine,
                                                             flag: "-import-objc-header",
                                                             filename: "header.pch"))
      XCTAssertEqual(plannedJobs[2].kind, .mergeModule)
      XCTAssertTrue(plannedJobs[2].commandLine.contains(subsequence:
                                                          ["-import-objc-header",
                                                           try toPathOption("header.h")]))
    }

    // Immediate mode doesn't generate a pch
    do {
      var driver = try Driver(args: ["swift", "-import-objc-header", "TestInputHeader.h", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      XCTAssertEqual(plannedJobs[0].kind, .interpret)
      XCTAssert(plannedJobs[0].commandLine.contains(.flag("-import-objc-header")))
      XCTAssert(plannedJobs[0].commandLine.contains(try toPathOption("TestInputHeader.h")))
    }
  }

  func testPCMGeneration() throws {
     do {
       var driver = try Driver(args: ["swiftc", "-emit-pcm", "module.modulemap", "-module-name", "Test"])
       let plannedJobs = try driver.planBuild()
       XCTAssertEqual(plannedJobs.count, 1)

       XCTAssertEqual(plannedJobs[0].kind, .generatePCM)
       XCTAssertEqual(plannedJobs[0].inputs.count, 1)
       XCTAssertEqual(plannedJobs[0].inputs[0].file, try toPath("module.modulemap"))
       XCTAssertEqual(plannedJobs[0].outputs.count, 1)
       XCTAssertEqual(plannedJobs[0].outputs[0].file, .relative(try RelativePath(validating: "Test.pcm")))
    }
  }

  func testPCMDump() throws {
    do {
      var driver = try Driver(args: ["swiftc", "-dump-pcm", "module.pcm"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)

      XCTAssertEqual(plannedJobs[0].kind, .dumpPCM)
      XCTAssertEqual(plannedJobs[0].inputs.count, 1)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, try toPath("module.pcm"))
      XCTAssertEqual(plannedJobs[0].outputs.count, 0)
    }
  }

  func testIndexFilePathHandling() throws {
    do {
      var driver = try Driver(args: ["swiftc", "-index-file", "-index-file-path",
                                     "bar.swift", "foo.swift", "bar.swift", "baz.swift",
                                     "-module-name", "Test"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 1)
      XCTAssertEqual(plannedJobs[0].kind, .compile)
      let job = plannedJobs[0]
      XCTAssertTrue(job.commandLine.contains(subsequence: [try toPathOption("foo.swift"),
                                                           "-primary-file",
                                                           try toPathOption("bar.swift"),
                                                           try toPathOption("baz.swift")]))
    }
  }

  func testEmbedBitcode() throws {
    do {
      var driver = try Driver(args: ["swiftc", "-embed-bitcode", "embed-bitcode.swift"])
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(plannedJobs.count, 3)

      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertEqual(plannedJobs[0].inputs.count, 1)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, try toPath("embed-bitcode.swift"))
      XCTAssertEqual(plannedJobs[0].outputs.count, 1)
      XCTAssertTrue(matchTemporary(plannedJobs[0].outputs[0].file, "embed-bitcode.bc"))

      XCTAssertEqual(plannedJobs[1].kind, .backend)
      XCTAssertEqual(plannedJobs[1].inputs.count, 1)
      XCTAssertTrue(matchTemporary(plannedJobs[1].inputs[0].file, "embed-bitcode.bc"))
      XCTAssertEqual(plannedJobs[1].outputs.count, 1)
      XCTAssertTrue(matchTemporary(plannedJobs[1].outputs[0].file, "embed-bitcode.o"))

      XCTAssertEqual(plannedJobs[2].kind, .link)
      XCTAssertEqual(plannedJobs[2].outputs.count, 1)
      XCTAssertEqual(plannedJobs[2].outputs[0].file, try toPath("embed-bitcode"))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-embed-bitcode", "main.swift", "hi.swift"])
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(plannedJobs.count, 5)

      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertEqual(plannedJobs[0].inputs.count, 2)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, try toPath("main.swift"))
      XCTAssertEqual(plannedJobs[0].inputs[1].file, try toPath("hi.swift"))
      XCTAssertEqual(plannedJobs[0].outputs.count, 1)
      XCTAssertTrue(matchTemporary(plannedJobs[0].outputs[0].file, "main.bc"))

      XCTAssertEqual(plannedJobs[1].kind, .backend)
      XCTAssertEqual(plannedJobs[1].inputs.count, 1)
      XCTAssertTrue(matchTemporary(plannedJobs[1].inputs[0].file, "main.bc"))
      XCTAssertEqual(plannedJobs[1].outputs.count, 1)
      XCTAssertTrue(matchTemporary(plannedJobs[1].outputs[0].file, "main.o"))

      XCTAssertEqual(plannedJobs[2].kind, .compile)
      XCTAssertEqual(plannedJobs[2].inputs.count, 2)
      XCTAssertEqual(plannedJobs[2].inputs[0].file, try toPath("main.swift"))
      XCTAssertEqual(plannedJobs[2].inputs[1].file, try toPath("hi.swift"))
      XCTAssertEqual(plannedJobs[2].outputs.count, 1)
      XCTAssertTrue(matchTemporary(plannedJobs[2].outputs[0].file, "hi.bc"))

      XCTAssertEqual(plannedJobs[3].kind, .backend)
      XCTAssertEqual(plannedJobs[3].inputs.count, 1)
      XCTAssertTrue(matchTemporary(plannedJobs[3].inputs[0].file, "hi.bc"))
      XCTAssertEqual(plannedJobs[3].outputs.count, 1)
      XCTAssertTrue(matchTemporary(plannedJobs[3].outputs[0].file, "hi.o"))

      XCTAssertEqual(plannedJobs[4].kind, .link)
    }

    do {
      var driver = try Driver(args: ["swiftc", "-embed-bitcode", "-c", "-emit-module", "embed-bitcode.swift"])
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(plannedJobs.count, 3)

      let compileJob = try plannedJobs.findJob(.compile)
      XCTAssertEqual(compileJob.inputs.count, 1)
      XCTAssertEqual(compileJob.inputs[0].file, try toPath("embed-bitcode.swift"))
      XCTAssertEqual(compileJob.outputs.count, 1)
      XCTAssertTrue(matchTemporary(compileJob.outputs[0].file, "embed-bitcode.bc"))

      let backendJob = try plannedJobs.findJob(.backend)
      XCTAssertEqual(backendJob.inputs.count, 1)
      XCTAssertTrue(matchTemporary(backendJob.inputs[0].file, "embed-bitcode.bc"))
      XCTAssertEqual(backendJob.outputs.count, 1)
      XCTAssertEqual(backendJob.outputs[0].file, try toPath("embed-bitcode.o"))

      let emitModuleJob = try plannedJobs.findJob(.emitModule)
      XCTAssertEqual(emitModuleJob.inputs.count, 1)
      XCTAssertEqual(emitModuleJob.inputs[0].file, try toPath("embed-bitcode.swift"))
      XCTAssertEqual(emitModuleJob.outputs.count, driver.targetTriple.isDarwin ? 4 : 3)
      XCTAssertEqual(emitModuleJob.outputs[0].file, try toPath("main.swiftmodule"))
      XCTAssertEqual(emitModuleJob.outputs[1].file, try toPath("main.swiftdoc"))
      XCTAssertEqual(emitModuleJob.outputs[2].file, try toPath("main.swiftsourceinfo"))
      if driver.targetTriple.isDarwin {
          XCTAssertEqual(emitModuleJob.outputs[3].file, try toPath("main.abi.json"))
      }
    }

    do {
      var driver = try Driver(args: ["swiftc", "-embed-bitcode", "-wmo", "embed-bitcode.swift"])
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(plannedJobs.count, 3)

      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertEqual(plannedJobs[0].inputs.count, 1)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, try toPath("embed-bitcode.swift"))
      XCTAssertEqual(plannedJobs[0].outputs.count, 1)
      XCTAssertTrue(matchTemporary(plannedJobs[0].outputs[0].file, "main.bc"))

      XCTAssertEqual(plannedJobs[1].kind, .backend)
      XCTAssertEqual(plannedJobs[1].inputs.count, 1)
      XCTAssertTrue(matchTemporary(plannedJobs[1].inputs[0].file, "main.bc"))
      XCTAssertEqual(plannedJobs[1].outputs.count, 1)
      XCTAssertTrue(matchTemporary(plannedJobs[1].outputs[0].file, "main.o"))

      XCTAssertEqual(plannedJobs[2].kind, .link)
      XCTAssertEqual(plannedJobs[2].outputs.count, 1)
      XCTAssertEqual(plannedJobs[2].outputs[0].file, try toPath("embed-bitcode"))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-embed-bitcode", "-c", "-parse-as-library", "-emit-module",  "embed-bitcode.swift", "empty.swift", "-module-name", "ABC"])
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(plannedJobs.count, 5)

      XCTAssertEqual(plannedJobs[1].kind, .compile)
      XCTAssertEqual(plannedJobs[1].outputs.count, 1)
      XCTAssertTrue(matchTemporary(plannedJobs[1].outputs[0].file, "embed-bitcode.bc"))

      XCTAssertEqual(plannedJobs[2].kind, .backend)
      XCTAssertEqual(plannedJobs[2].inputs.count, 1)
      XCTAssertTrue(matchTemporary(plannedJobs[2].inputs[0].file, "embed-bitcode.bc"))
      XCTAssertEqual(plannedJobs[2].outputs.count, 1)
      XCTAssertEqual(plannedJobs[2].outputs[0].file, try toPath("embed-bitcode.o"))

      XCTAssertEqual(plannedJobs[3].kind, .compile)
      XCTAssertEqual(plannedJobs[3].outputs.count, 1)
      XCTAssertTrue(matchTemporary(plannedJobs[3].outputs[0].file, "empty.bc"))

      XCTAssertEqual(plannedJobs[4].kind, .backend)
      XCTAssertEqual(plannedJobs[4].inputs.count, 1)
      XCTAssertTrue(matchTemporary(plannedJobs[4].inputs[0].file, "empty.bc"))

      XCTAssertEqual(plannedJobs[4].outputs.count, 1)
      XCTAssertEqual(plannedJobs[4].outputs[0].file, try toPath("empty.o"))

      let emitModuleJob = try plannedJobs.findJob(.emitModule)
      XCTAssertEqual(emitModuleJob.inputs.count, 2)
      XCTAssertEqual(emitModuleJob.inputs[0].file, try toPath("embed-bitcode.swift"))
      XCTAssertEqual(emitModuleJob.inputs[1].file, try toPath("empty.swift"))
      XCTAssertEqual(emitModuleJob.outputs.count, driver.targetTriple.isDarwin ? 4 : 3)
      XCTAssertEqual(emitModuleJob.outputs[0].file, try toPath("ABC.swiftmodule"))
      XCTAssertEqual(emitModuleJob.outputs[1].file, try toPath("ABC.swiftdoc"))
      XCTAssertEqual(emitModuleJob.outputs[2].file, try toPath("ABC.swiftsourceinfo"))
      if driver.targetTriple.isDarwin {
          XCTAssertEqual(emitModuleJob.outputs[3].file, try toPath("ABC.abi.json"))
      }
    }

    do {
      var driver = try Driver(args: ["swiftc", "-embed-bitcode", "-c", "-parse-as-library", "-emit-module", "-whole-module-optimization", "embed-bitcode.swift", "-parse-stdlib", "-module-name", "Swift"])
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(plannedJobs.count, 3)

      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssertEqual(plannedJobs[0].inputs.count, 1)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, try toPath("embed-bitcode.swift"))
      XCTAssertEqual(plannedJobs[0].outputs.count, 1)
      XCTAssertTrue(matchTemporary(plannedJobs[0].outputs[0].file, "Swift.bc"))

      XCTAssertEqual(plannedJobs[1].kind, .backend)
      XCTAssertEqual(plannedJobs[1].inputs.count, 1)
      XCTAssertTrue(matchTemporary(plannedJobs[1].inputs[0].file, "Swift.bc"))
      XCTAssertEqual(plannedJobs[1].outputs.count, 1)
      XCTAssertEqual(plannedJobs[1].outputs[0].file, try toPath("Swift.o"))

      let emitModuleJob = plannedJobs[2]
      XCTAssertEqual(emitModuleJob.kind, .emitModule)
      XCTAssertEqual(emitModuleJob.inputs.count, 1)
      XCTAssertEqual(plannedJobs[0].inputs[0].file, try toPath("embed-bitcode.swift"))
      XCTAssertEqual(emitModuleJob.outputs.count, driver.targetTriple.isDarwin ? 4 : 3)
      XCTAssertEqual(1, try emitModuleJob.outputs.filter({try toPath("Swift.swiftmodule") == $0.file}).count)
      XCTAssertEqual(1, try emitModuleJob.outputs.filter({try toPath("Swift.swiftdoc") == $0.file}).count)
      XCTAssertEqual(1, try emitModuleJob.outputs.filter({try toPath("Swift.swiftsourceinfo") == $0.file}).count)
      if driver.targetTriple.isDarwin {
          XCTAssertEqual(1, try emitModuleJob.outputs.filter({try toPath("Swift.abi.json") == $0.file}).count)
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode", "-emit-module", "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode")))
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode", "-emit-module-path", "a.swiftmodule",  "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode")))
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode", "-emit-sib", "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode")))
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode", "-emit-sibgen", "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode")))
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode", "-emit-sil", "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode")))
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode", "-emit-silgen", "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode")))
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode", "-emit-ir", "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode")))
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode", "-emit-bc", "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode")))
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode", "-emit-assembly", "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode")))
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode-marker", "-emit-module", "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode-marker since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode-marker")))
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode-marker", "-emit-module-path", "a.swiftmodule",  "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode-marker since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode-marker")))
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode-marker", "-emit-sib", "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode-marker since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode-marker")))
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode-marker", "-emit-sibgen", "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode-marker since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode-marker")))
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode-marker", "-emit-sil", "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode-marker since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode-marker")))
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode-marker", "-emit-silgen", "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode-marker since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode-marker")))
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode-marker", "-emit-ir", "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode-marker since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode-marker")))
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode-marker", "-emit-bc", "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode-marker since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode-marker")))
      }
    }

    try assertDriverDiagnostics(args: ["swiftc", "-embed-bitcode-marker", "-emit-assembly", "embed-bitcode.swift"]) { driver, verify in
      verify.expect(.warning("ignoring -embed-bitcode-marker since no object file is being generated"))
      let plannedJobs = try driver.planBuild()

      for job in plannedJobs {
        XCTAssertFalse(job.commandLine.contains(.flag("-embed-bitcode-marker")))
      }
    }
  }

  func testCXXInteropOptions() throws {
    do {
      var driver = try Driver(args: ["swiftc", "-cxx-interoperability-mode=swift-5.9", "foo.swift"])
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(plannedJobs.count, 2)
      let compileJob = plannedJobs[0]
      let linkJob = plannedJobs[1]
      XCTAssertTrue(compileJob.commandLine.contains(.flag("-cxx-interoperability-mode=swift-5.9")))
      if driver.targetTriple.isDarwin {
        XCTAssertTrue(linkJob.commandLine.contains(.flag("-lc++")))
      }
    }
    do {
      var driver = try Driver(args: ["swiftc", "-cxx-interoperability-mode=swift-5.9",
                                     "-experimental-cxx-stdlib", "libc++", "foo.swift"])
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(plannedJobs.count, 2)
      let compileJob = plannedJobs[0]
      let linkJob = plannedJobs[1]
      XCTAssertTrue(compileJob.commandLine.contains(.flag("-cxx-interoperability-mode=swift-5.9")))
      XCTAssertTrue(compileJob.commandLine.contains(.flag("-stdlib=libc++")))
      if driver.targetTriple.isDarwin {
        XCTAssertTrue(linkJob.commandLine.contains(.flag("-lc++")))
      }
    }
  }

  func testEmbeddedSwiftOptions() throws {
    var env = ProcessEnv.vars
    env["SWIFT_DRIVER_SWIFT_AUTOLINK_EXTRACT_EXEC"] = "/garbage/swift-autolink-extract"

    do {
      var driver = try Driver(args: ["swiftc", "-target", "arm64-apple-macosx10.13",  "test.swift", "-enable-experimental-feature", "Embedded", "-parse-as-library", "-wmo", "-o", "a.out", "-module-name", "main"])
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 2)
      let compileJob = plannedJobs[0]
      let linkJob = plannedJobs[1]
      XCTAssertTrue(compileJob.commandLine.contains(.flag("-disable-objc-interop")))
      XCTAssertFalse(linkJob.commandLine.contains(.flag("-force_load")))
    }
    
    do {
      var driver = try Driver(args: [
        "swiftc",
        "-v",
        "-L",
        "/TestApp/.build/aarch64-none-none-elf/release",
        "-o",
        "/TestApp/.build/aarch64-none-none-elf/release/TestApp",
        "-module-name",
        "TestApp",
        "-emit-executable",
        "-Xlinker",
        "--gc-sections",
        "@/TestApp/.build/aarch64-none-none-elf/release/TestApp.product/Objects.LinkFileList",
        "-target",
        "aarch64-none-none-elf",
        "-enable-experimental-feature", "Embedded",
        "-Xfrontend",
        "-function-sections",
        "-Xfrontend",
        "-disable-stack-protector",
        "-use-ld=lld",
        "-tools-directory",
        "/Tools/swift.xctoolchain/usr/bin",
      ], env: env)
      
      let jobs = try driver.planBuild()
      let linkJob = try jobs.findJob(.link)
      let invalidPath = try VirtualPath(path: "/Tools/swift.xctoolchain/usr/lib/swift")
      let invalid = linkJob.commandLine.contains(.responseFilePath(invalidPath))
      XCTAssertFalse(invalid) // ensure the driver does not emit invalid responseFilePaths to the clang invocation
      XCTAssertFalse(linkJob.commandLine.joinedUnresolvedArguments.contains("swiftrt.o"))
    }
    
    // Embedded Wasm compile job
    do {
      var driver = try Driver(args: ["swiftc", "-target", "wasm32-none-none-wasm", "test.swift", "-enable-experimental-feature", "Embedded", "-wmo", "-o", "a.wasm"], env: env)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 3)
      let compileJob = plannedJobs[0]
      let _ /*autolinkJob*/ = plannedJobs[1]
      let linkJob = plannedJobs[2]
      XCTAssertTrue(compileJob.commandLine.contains(.flag("-disable-objc-interop")))
      XCTAssertFalse(linkJob.commandLine.contains(.flag("-force_load")))
      XCTAssertFalse(linkJob.commandLine.contains(.flag("-rpath")))
      XCTAssertFalse(linkJob.commandLine.contains(.flag("-lswiftCore")))
    }

    // Embedded Wasm link job
    do {
      var driver = try Driver(args: ["swiftc", "-target", "wasm32-none-none-wasm", "test.o", "-enable-experimental-feature", "Embedded", "-wmo", "-o", "a.wasm"], env: env)
      let plannedJobs = try driver.planBuild()
      XCTAssertEqual(plannedJobs.count, 2)
      let _ /*autolinkJob*/ = plannedJobs[0]
      let linkJob = plannedJobs[1]
      XCTAssertFalse(linkJob.commandLine.contains(.flag("-force_load")))
      XCTAssertFalse(linkJob.commandLine.contains(.flag("-rpath")))
      XCTAssertFalse(linkJob.commandLine.contains(.flag("-lswiftCore")))
      XCTAssertFalse(linkJob.commandLine.joinedUnresolvedArguments.contains("swiftrt.o"))
    }

    do {
      let diags = DiagnosticsEngine()
      var driver = try Driver(args: ["swiftc", "-target", "arm64-apple-macosx10.13",  "test.swift", "-enable-experimental-feature", "Embedded", "-parse-as-library", "-wmo", "-o", "a.out", "-module-name", "main", "-enable-library-evolution"], diagnosticsEngine: diags)
      _ = try driver.planBuild()
      XCTAssertTrue(diags.diagnostics.first!.message.text == Diagnostic.Message.error_no_library_evolution_embedded.text)
    } catch _ { }
    do {
      let diags = DiagnosticsEngine()
      var driver = try Driver(args: ["swiftc", "-target", "arm64-apple-macosx10.13",  "test.swift", "-enable-experimental-feature", "Embedded", "-parse-as-library", "-o", "a.out", "-module-name", "main"], diagnosticsEngine: diags)
      _ = try driver.planBuild()
      XCTAssertTrue(diags.diagnostics.first!.message.text == Diagnostic.Message.error_need_wmo_embedded.text)
    } catch _ { }
    do {
      let diags = DiagnosticsEngine()
      var driver = try Driver(args: ["swiftc", "-target", "arm64-apple-macosx10.13",  "test.swift", "-enable-experimental-feature", "Embedded", "-parse-as-library", "-wmo", "-o", "a.out", "-module-name", "main", "-enable-objc-interop"], diagnosticsEngine: diags)
      _ = try driver.planBuild()
      XCTAssertTrue(diags.diagnostics.first!.message.text == Diagnostic.Message.error_no_objc_interop_embedded.text)
    } catch _ { }
  }

  func testVFSOverlay() throws {
    do {
      var driver = try Driver(args: ["swiftc", "-c", "-vfsoverlay", "overlay.yaml", "foo.swift"])
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(plannedJobs.count, 1)
      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssert(plannedJobs[0].commandLine.contains(subsequence: [.flag("-vfsoverlay"), try toPathOption("overlay.yaml")]))
    }

    // Verify that the overlays are passed to the frontend in the same order.
    do {
      var driver = try Driver(args: ["swiftc", "-c", "-vfsoverlay", "overlay1.yaml", "-vfsoverlay", "overlay2.yaml", "-vfsoverlay", "overlay3.yaml", "foo.swift"])
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(plannedJobs.count, 1)
      XCTAssertEqual(plannedJobs[0].kind, .compile)
      XCTAssert(plannedJobs[0].commandLine.contains(subsequence: [.flag("-vfsoverlay"), try toPathOption("overlay1.yaml"), .flag("-vfsoverlay"), try toPathOption("overlay2.yaml"), .flag("-vfsoverlay"), try toPathOption("overlay3.yaml")]))
    }
  }

  func testSwiftHelpOverride() throws {
    // FIXME: On Linux, we might not have any Clang in the path. We need a
    // better override.
    var env = ProcessEnv.vars
    let swiftHelp: AbsolutePath = try AbsolutePath(validating: "/usr/bin/nonexistent-swift-help")
    env["SWIFT_DRIVER_SWIFT_HELP_EXEC"] = swiftHelp.pathString
    env["SWIFT_DRIVER_CLANG_EXEC"] = "/usr/bin/clang"
    var driver = try Driver(
      args: ["swiftc", "-help"],
      env: env)
    let jobs = try driver.planBuild()
    XCTAssert(jobs.count == 1)
    XCTAssertEqual(jobs.first!.tool.name, swiftHelp.pathString)
  }

  func testSwiftClangOverride() throws {
    var env = ProcessEnv.vars
    let swiftClang = try AbsolutePath(validating: "/A/Path/swift-clang")
    env["SWIFT_DRIVER_CLANG_EXEC"] = swiftClang.pathString

    var driver = try Driver(
      args: ["swiftc", "-emit-library", "foo.swift", "bar.o", "-o", "foo.l"],
      env: env)
    let jobs = try driver.planBuild()
    XCTAssertEqual(jobs.count, 2)
    let linkJob = jobs[1]
    XCTAssertEqual(linkJob.tool.name, swiftClang.pathString)
  }

  func testSwiftClangxxOverride() throws {
#if os(iOS) || os(macOS) || os(tvOS) || os(watchOS)
      throw XCTSkip("Darwin always uses `clang` to link")
#else
    var env = ProcessEnv.vars
    let swiftClang = try AbsolutePath(validating: "/A/Path/swift-clang")
    let swiftClangxx = try AbsolutePath(validating: "/A/Path/swift-clang++")
    env["SWIFT_DRIVER_CLANG_EXEC"] = swiftClang.pathString
    env["SWIFT_DRIVER_CLANGXX_EXEC"] = swiftClangxx.pathString

    var driver = try Driver(
      args: ["swiftc", "-cxx-interoperability-mode=swift-5.9", "-emit-library",
             "foo.swift", "bar.o", "-o", "foo.l"],
      env: env)

    let jobs = try driver.planBuild()
    let linkJob = jobs.last!
    XCTAssertEqual(linkJob.tool.name, swiftClangxx.pathString)
#endif
  }

  func testSourceInfoFileEmitOption() throws {
    // implicit
    do {
      var driver = try Driver(args: ["swiftc", "-emit-module", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      let emitModuleJob = plannedJobs[0]
      XCTAssertTrue(emitModuleJob.commandLine.contains(.flag("-emit-module-source-info-path")))
      XCTAssertEqual(emitModuleJob.outputs.count, driver.targetTriple.isDarwin ? 4 : 3)
      XCTAssertEqual(emitModuleJob.outputs[0].file, try toPath("foo.swiftmodule"))
      XCTAssertEqual(emitModuleJob.outputs[1].file, try toPath("foo.swiftdoc"))
      XCTAssertEqual(emitModuleJob.outputs[2].file, try toPath("foo.swiftsourceinfo"))
      if driver.targetTriple.isDarwin {
          XCTAssertEqual(emitModuleJob.outputs[3].file, try toPath("foo.abi.json"))
      }
    }
    // implicit with Project/ Directory
    do {
      try withTemporaryDirectory { path in
        let projectDirPath = path.appending(component: "Project")
        try localFileSystem.createDirectory(projectDirPath)
        var driver = try Driver(args: ["swiftc", "-emit-module",
                                       path.appending(component: "foo.swift").description,
                                       "-o", path.appending(component: "foo.swiftmodule").description])
        let plannedJobs = try driver.planBuild()
        let emitModuleJob = plannedJobs[0]
        XCTAssertTrue(emitModuleJob.commandLine.contains(.flag("-emit-module-source-info-path")))
        XCTAssertEqual(emitModuleJob.outputs.count, driver.targetTriple.isDarwin ? 4 : 3)
        XCTAssertEqual(emitModuleJob.outputs[0].file, .absolute(path.appending(component: "foo.swiftmodule")))
        XCTAssertEqual(emitModuleJob.outputs[1].file, .absolute(path.appending(component: "foo.swiftdoc")))
        XCTAssertEqual(emitModuleJob.outputs[2].file, .absolute(projectDirPath.appending(component: "foo.swiftsourceinfo")))
        if driver.targetTriple.isDarwin {
          XCTAssertEqual(emitModuleJob.outputs[3].file, .absolute(path.appending(component: "foo.abi.json")))
        }
      }
    }
    // avoid implicit swiftsourceinfo
    do {
      var driver = try Driver(args: ["swiftc", "-emit-module", "-avoid-emit-module-source-info", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      let emitModuleJob = plannedJobs[0]
      XCTAssertFalse(emitModuleJob.commandLine.contains(.flag("-emit-module-source-info-path")))
      XCTAssertEqual(emitModuleJob.outputs.count, driver.targetTriple.isDarwin ? 3 : 2)
      XCTAssertEqual(emitModuleJob.outputs[0].file, try toPath("foo.swiftmodule"))
      XCTAssertEqual(emitModuleJob.outputs[1].file, try toPath("foo.swiftdoc"))
      if driver.targetTriple.isDarwin {
          XCTAssertEqual(emitModuleJob.outputs[2].file, try toPath("foo.abi.json"))
      }
    }
  }

  func testUseStaticResourceDir() throws {
    do {
      var driver = try Driver(args: ["swiftc", "-emit-module", "-target", "x86_64-unknown-linux", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      let job = plannedJobs[0]
      XCTAssertFalse(job.commandLine.contains(.flag("-use-static-resource-dir")))
      XCTAssertEqual(VirtualPath.lookup(driver.frontendTargetInfo.runtimeResourcePath.path).basename, "swift")
    }

    do {
      var driver = try Driver(args: ["swiftc", "-emit-module", "-target", "x86_64-unknown-linux", "-no-static-executable", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      let job = plannedJobs[0]
      XCTAssertFalse(job.commandLine.contains(.flag("-use-static-resource-dir")))
      XCTAssertEqual(VirtualPath.lookup(driver.frontendTargetInfo.runtimeResourcePath.path).basename, "swift")
    }

    do {
      var driver = try Driver(args: ["swiftc", "-emit-module", "-target", "x86_64-unknown-linux", "-no-static-stdlib", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      let job = plannedJobs[0]
      XCTAssertFalse(job.commandLine.contains(.flag("-use-static-resource-dir")))
      XCTAssertEqual(VirtualPath.lookup(driver.frontendTargetInfo.runtimeResourcePath.path).basename, "swift")
    }

    do {
      var driver = try Driver(args: ["swiftc", "-emit-module", "-target", "x86_64-unknown-linux", "-static-executable", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      let job = plannedJobs[0]
      XCTAssertTrue(job.commandLine.contains(.flag("-use-static-resource-dir")))
      XCTAssertEqual(VirtualPath.lookup(driver.frontendTargetInfo.runtimeResourcePath.path).basename, "swift_static")
    }

    do {
      var driver = try Driver(args: ["swiftc", "-emit-module", "-target", "x86_64-unknown-linux", "-static-stdlib", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      let job = plannedJobs[0]
      XCTAssertTrue(job.commandLine.contains(.flag("-use-static-resource-dir")))
      XCTAssertEqual(VirtualPath.lookup(driver.frontendTargetInfo.runtimeResourcePath.path).basename, "swift_static")
    }
  }

  func testFrontendTargetInfoWithWorkingDirectory() throws {
    do {
      let workingDirectory = localFileSystem.currentWorkingDirectory!.appending(components: "absolute", "path")

      var driver = try Driver(args: ["swiftc", "-typecheck", "foo.swift",
                                     "-resource-dir", "resource/dir",
                                     "-sdk", "sdk",
                                     "-working-directory", workingDirectory.pathString])
      let plannedJobs = try driver.planBuild()
      let job = plannedJobs[0]
      XCTAssertTrue(job.commandLine.contains(.path(try VirtualPath(path: rebase("resource", "dir", at: workingDirectory)))))
      XCTAssertFalse(job.commandLine.contains(.path(.relative(try .init(validating: "resource/dir")))))
      XCTAssertTrue(job.commandLine.contains(.path(try VirtualPath(path: rebase("sdk", at: workingDirectory)))))
      XCTAssertFalse(job.commandLine.contains(.path(.relative(try .init(validating: "sdk")))))
    }
  }

  func testWarnConcurrency() throws {
    do {
      var driver = try Driver(args: ["swiftc", "-warn-concurrency", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      let job = plannedJobs[0]
      XCTAssertTrue(job.commandLine.contains(.flag("-warn-concurrency")))
    }
  }

  func testLibraryLevel() throws {
    do {
      var driver = try Driver(args: ["swiftc", "-library-level", "spi", "foo.swift"])
      let plannedJobs = try driver.planBuild()
      let job = plannedJobs[0]
      XCTAssertTrue(job.commandLine.contains(subsequence: [.flag("-library-level"), .flag("spi")]))
    }
  }

  func testPrebuiltModuleCacheFlags() throws {
    var envVars = ProcessEnv.vars
    envVars["SWIFT_DRIVER_LD_EXEC"] = ld.nativePathString(escaped: false)

    let mockSDKPath: String =
        try testInputsPath.appending(component: "mock-sdk.sdk").nativePathString(escaped: false)

    do {
      var driver = try Driver(args: ["swiftc", "-target", "x86_64-apple-ios13.1-macabi", "foo.swift", "-sdk", mockSDKPath],
                              env: envVars)
      let plannedJobs = try driver.planBuild()
      let job = plannedJobs[0]
      XCTAssertTrue(job.commandLine.contains(.flag("-prebuilt-module-cache-path")))
      XCTAssertTrue(job.commandLine.contains { arg in
        if case .path(let curPath) = arg {
          if curPath.basename == "10.15" && curPath.parentDirectory.basename == "prebuilt-modules" {
              return true
          }
        }
        return false
      })
    }
  }

  func testRelativeResourceDir() throws {
    do {
      var driver = try Driver(args: ["swiftc",
                                     "-target", "x86_64-unknown-linux", "-lto=llvm-thin",
                                     "foo.swift",
                                     "-resource-dir", "resource/dir"])
      let plannedJobs = try driver.planBuild().removingAutolinkExtractJobs()
      let compileJob = plannedJobs[0]
      XCTAssertEqual(compileJob.kind, .compile)
      XCTAssertTrue(compileJob.commandLine.contains(subsequence: ["-resource-dir", try toPathOption("resource/dir")]))
      let linkJob = plannedJobs[1]
      XCTAssertEqual(linkJob.kind, .link)
      XCTAssertTrue(linkJob.commandLine.contains(subsequence:
                                              ["-Xlinker", "-rpath",
                                               "-Xlinker", try toPathOption("resource/dir/linux")]))
      XCTAssertTrue(linkJob.commandLine.contains(try toPathOption("resource/dir/linux/x86_64/swiftrt.o")))
      XCTAssertTrue(linkJob.commandLine.contains(subsequence:
                                                   ["-L", try toPathOption("resource/dir/linux")]))
    }
  }

  func testSanitizerArgsForTargets() throws {
    let targets = ["x86_64-unknown-freebsd",  "x86_64-unknown-linux", "x86_64-apple-macosx10.9"]
    try targets.forEach {
      var driver = try Driver(args: ["swiftc", "-emit-module", "-target", $0, "foo.swift"])
      _ = try driver.planBuild()
      XCTAssertFalse(driver.diagnosticEngine.hasErrors)
    }
  }

  func testIsIosMacInterface() throws {
    try withTemporaryFile { file in
      try localFileSystem.writeFileContents(file.path, bytes: "// swift-module-flags: -target x86_64-apple-ios15.0-macabi")
      XCTAssertTrue(try isIosMacInterface(VirtualPath.absolute(file.path)))
    }
    try withTemporaryFile { file in
      try localFileSystem.writeFileContents(file.path, bytes: "// swift-module-flags: -target arm64e-apple-macos12.0")
      XCTAssertFalse(try isIosMacInterface(VirtualPath.absolute(file.path)))
    }
  }

  func testAdopterConfigFile() throws {
    try withTemporaryFile { file in
      try localFileSystem.writeFileContents(file.path, bytes:
        #"""
        [
          {
            "key": "SkipFeature1",
            "moduleNames": ["foo", "bar"]
          }
        ]
        """#
      )
      let configs = Driver.parseAdopterConfigs(file.path)
      XCTAssertEqual(configs.count, 1)
      XCTAssertEqual(configs[0].key, "SkipFeature1")
      XCTAssertEqual(configs[0].moduleNames, ["foo", "bar"])
      let modules = Driver.getAllConfiguredModules(withKey: "SkipFeature1", configs)
      XCTAssertTrue(modules.contains("foo"))
      XCTAssertTrue(modules.contains("bar"))
      XCTAssertTrue(Driver.getAllConfiguredModules(withKey: "SkipFeature2", configs).isEmpty)
    }
    try withTemporaryFile { file in
      try localFileSystem.writeFileContents(file.path, bytes: "][ malformed }{")
      let configs = Driver.parseAdopterConfigs(file.path)
      XCTAssertEqual(configs.count, 0)
    }
    do {
      let configs = Driver.parseAdopterConfigs(try AbsolutePath(validating: "/abc/c/a.json"))
      XCTAssertEqual(configs.count, 0)
    }
  }

  func testExtractPackageName() throws {
    try withTemporaryFile { file in
      try localFileSystem.writeFileContents(file.path, bytes:
        """
        // swift-module-flags: -target arm64e-apple-macos12.0
        // swift-module-flags-ignorable: -library-level api\
        // swift-module-flags-ignorable-private: -package-name myPkg
        """
      )
      let flags = try getAllModuleFlags(VirtualPath.absolute(file.path))
      let idx = flags.firstIndex(of: "-package-name")
      XCTAssertNotNil(idx)
      XCTAssert(idx! + 1 < flags.count)
      XCTAssertEqual(flags[idx! + 1], "myPkg")
    }
  }

  func testExtractLibraryLevel() throws {
    try withTemporaryFile { file in
      try localFileSystem.writeFileContents(file.path, bytes: "// swift-module-flags: -library-level api")
      let flags = try getAllModuleFlags(VirtualPath.absolute(file.path))
      XCTAssertEqual(try getLibraryLevel(flags), .api)
    }
    try withTemporaryFile { file in
      try localFileSystem.writeFileContents(file.path, bytes:
        """
        // swift-module-flags: -target arm64e-apple-macos12.0
        // swift-module-flags-ignorable: -library-level spi
        """
      )
      let flags = try getAllModuleFlags(VirtualPath.absolute(file.path))
      XCTAssertEqual(try getLibraryLevel(flags), .spi)
    }
    try withTemporaryFile { file in
      try localFileSystem.writeFileContents(file.path, bytes: 
        "// swift-module-flags: -target arm64e-apple-macos12.0"
      )
      let flags = try getAllModuleFlags(VirtualPath.absolute(file.path))
      XCTAssertEqual(try getLibraryLevel(flags), .unspecified)
    }
  }

  func testSupportedFeatureJson() throws {
    let driver = try Driver(args: ["swiftc", "-emit-module", "foo.swift"])
    XCTAssertFalse(driver.supportedFrontendFeatures.isEmpty)
    XCTAssertTrue(driver.supportedFrontendFeatures.contains("experimental-skip-all-function-bodies"))
  }

  func testFilelist() throws {
    var envVars = ProcessEnv.vars
    envVars["SWIFT_DRIVER_LD_EXEC"] = ld.nativePathString(escaped: false)

    do {
      var driver = try Driver(args: ["swiftc", "-emit-module", "./a.swift", "./b.swift", "./c.swift", "-module-name", "main", "-target", "x86_64-apple-macosx10.9", "-driver-filelist-threshold=0", "-no-emit-module-separately"],
                              env: envVars)
      let plannedJobs = try driver.planBuild()

      let jobA = plannedJobs[0]
      let mapA = try XCTUnwrap(jobA.commandLine.supplementaryOutputFilemap)
      let filesA = try XCTUnwrap(mapA.entries[try toPath("a.swift").intern()])
      XCTAssertTrue(filesA.keys.contains(.swiftModule))
      XCTAssertTrue(filesA.keys.contains(.swiftDocumentation))
      XCTAssertTrue(filesA.keys.contains(.swiftSourceInfoFile))

      let jobB = plannedJobs[1]
      let mapB = try XCTUnwrap(jobB.commandLine.supplementaryOutputFilemap)
      let filesB = try XCTUnwrap(mapB.entries[try toPath("b.swift").intern()])
      XCTAssertTrue(filesB.keys.contains(.swiftModule))
      XCTAssertTrue(filesB.keys.contains(.swiftDocumentation))
      XCTAssertTrue(filesB.keys.contains(.swiftSourceInfoFile))

      let jobC = plannedJobs[2]
      let mapC = try XCTUnwrap(jobC.commandLine.supplementaryOutputFilemap)
      let filesC = try XCTUnwrap(mapC.entries[try toPath("c.swift").intern()])
      XCTAssertTrue(filesC.keys.contains(.swiftModule))
      XCTAssertTrue(filesC.keys.contains(.swiftDocumentation))
      XCTAssertTrue(filesC.keys.contains(.swiftSourceInfoFile))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-c", "./a.swift", "./b.swift", "./c.swift", "-module-name", "main", "-target", "x86_64-apple-macosx10.9", "-driver-filelist-threshold=0", "-whole-module-optimization"],
                              env: envVars)
      let plannedJobs = try driver.planBuild()
      let job = plannedJobs[0]
      let inputsFlag = job.commandLine.firstIndex(of: .flag("-filelist"))!
      let inputFileListArgument = job.commandLine[job.commandLine.index(after: inputsFlag)]
      guard case let .path(.fileList(_, inputFileList)) = inputFileListArgument else {
        XCTFail("Argument wasn't a filelist")
        return
      }
      guard case let .list(inputs) = inputFileList else {
        XCTFail("FileList wasn't List")
        return
      }
      XCTAssertEqual(inputs, [try toPath("a.swift"), try toPath("b.swift"), try toPath("c.swift")])

      let outputsFlag = job.commandLine.firstIndex(of: .flag("-output-filelist"))!
      let outputFileListArgument = job.commandLine[job.commandLine.index(after: outputsFlag)]
      guard case let .path(.fileList(_, outputFileList)) = outputFileListArgument else {
        XCTFail("Argument wasn't a filelist")
        return
      }
      guard case let .list(outputs) = outputFileList else {
        XCTFail("FileList wasn't List")
        return
      }
      XCTAssertEqual(outputs, [try toPath("main.o")])
    }

    do {
      var driver = try Driver(args: ["swiftc", "-c", "./a.swift", "./b.swift", "./c.swift", "-module-name", "main", "-target", "x86_64-apple-macosx10.9", "-driver-filelist-threshold=0", "-whole-module-optimization", "-num-threads", "1"],
                              env: envVars)
      let plannedJobs = try driver.planBuild()
      let job = plannedJobs[0]
      let outputsFlag = job.commandLine.firstIndex(of: .flag("-output-filelist"))!
      let outputFileListArgument = job.commandLine[job.commandLine.index(after: outputsFlag)]
      guard case let .path(.fileList(_, outputFileList)) = outputFileListArgument else {
        XCTFail("Argument wasn't a filelist")
        return
      }
      guard case let .list(outputs) = outputFileList else {
        XCTFail("FileList wasn't List")
        return
      }
      XCTAssertEqual(outputs, [try toPath("a.o"), try toPath("b.o"), try toPath("c.o")])
    }

    do {
      var driver = try Driver(args: ["swiftc", "-c", "./a.swift", "./b.swift", "./c.swift", "-module-name", "main", "-target", "x86_64-apple-macosx10.9", "-driver-filelist-threshold=0", "-whole-module-optimization", "-num-threads", "1", "-embed-bitcode"],
                              env: envVars)
      let plannedJobs = try driver.planBuild()
      let job = plannedJobs[0]
      let outputsFlag = job.commandLine.firstIndex(of: .flag("-output-filelist"))!
      let outputFileListArgument = job.commandLine[job.commandLine.index(after: outputsFlag)]
      guard case let .path(.fileList(_, outputFileList)) = outputFileListArgument else {
        XCTFail("Argument wasn't a filelist")
        return
      }
      guard case let .list(outputs) = outputFileList else {
        XCTFail("FileList wasn't List")
        return
      }
      XCTAssertTrue(outputs.count == 3)
      XCTAssertTrue(matchTemporary(outputs[0], "a.bc"))
      XCTAssertTrue(matchTemporary(outputs[1], "b.bc"))
      XCTAssertTrue(matchTemporary(outputs[2], "c.bc"))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-emit-library", "./a.swift", "./b.swift", "./c.swift", "-module-name", "main", "-target", "x86_64-apple-macosx10.9", "-driver-filelist-threshold=0"],
                              env: envVars)
      let plannedJobs = try driver.planBuild()
      let job = plannedJobs[3]
      let inputsFlag = job.commandLine.firstIndex(of: .flag("-filelist"))!
      let inputFileListArgument = job.commandLine[job.commandLine.index(after: inputsFlag)]
      guard case let .path(.fileList(_, inputFileList)) = inputFileListArgument else {
        XCTFail("Argument wasn't a filelist")
        return
      }
      guard case let .list(inputs) = inputFileList else {
        XCTFail("FileList wasn't List")
        return
      }
      XCTAssertTrue(inputs.count == 3)
      XCTAssertTrue(matchTemporary(inputs[0], "a.o"))
      XCTAssertTrue(matchTemporary(inputs[1], "b.o"))
      XCTAssertTrue(matchTemporary(inputs[2], "c.o"))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-emit-library", "./a.swift", "./b.swift", "./c.swift", "-module-name", "main", "-target", "x86_64-apple-macosx10.9", "-driver-filelist-threshold=0", "-whole-module-optimization", "-num-threads", "1"],
                              env: envVars)
      let plannedJobs = try driver.planBuild()
      let job = plannedJobs[1]
      let inputsFlag = job.commandLine.firstIndex(of: .flag("-filelist"))!
      let inputFileListArgument = job.commandLine[job.commandLine.index(after: inputsFlag)]
      guard case let .path(.fileList(_, inputFileList)) = inputFileListArgument else {
        XCTFail("Argument wasn't a filelist")
        return
      }
      guard case let .list(inputs) = inputFileList else {
        XCTFail("FileList wasn't List")
        return
      }
      XCTAssertTrue(inputs.count == 3)
      XCTAssertTrue(matchTemporary(inputs[0], "a.o"))
      XCTAssertTrue(matchTemporary(inputs[1], "b.o"))
      XCTAssertTrue(matchTemporary(inputs[2], "c.o"))
    }

    do {
      var driver = try Driver(args: ["swiftc", "-typecheck", "a.swift", "b.swift", "-driver-filelist-threshold=0"])
      let plannedJobs = try driver.planBuild()

      let jobA = plannedJobs[0]
      let mapA = try XCTUnwrap(jobA.commandLine.supplementaryOutputFilemap)
      XCTAssertEqual(mapA.entries, [try toPath("a.swift").intern(): [:]])

      let jobB = plannedJobs[1]
      let mapB = try XCTUnwrap(jobB.commandLine.supplementaryOutputFilemap)
      XCTAssertEqual(mapB.entries, [try toPath("b.swift").intern(): [:]])
    }

    do {
      var driver = try Driver(args: ["swiftc", "-typecheck", "-wmo", "a.swift", "b.swift", "-driver-filelist-threshold=0"])
      let plannedJobs = try driver.planBuild()

      let jobA = plannedJobs[0]
      let mapA = try XCTUnwrap(jobA.commandLine.supplementaryOutputFilemap)
      XCTAssertEqual(mapA.entries, [try toPath("a.swift").intern(): [:]])
    }
  }

  func testSaveUnkownDriverFlags() throws {
    do {
      var driver = try Driver(args: ["swiftc", "-typecheck", "a.swift", "b.swift", "-unlikely-flag-for-testing"])
      let plannedJobs = try driver.planBuild()
      let jobA = plannedJobs[0]
      XCTAssertTrue(jobA.commandLine.contains("-unlikely-flag-for-testing"))
    }
  }

  func testCleaningUpOldCompilationOutputs() throws {
#if !os(macOS)
    throw XCTSkip("sdkArguments does not work on Linux")
#else
    // Build something, create an error, see if the .o and .swiftdeps files get cleaned up
    try withTemporaryDirectory { tmpDir in
      let main = tmpDir.appending(component: "main.swift")
      let ofm = tmpDir.appending(component: "ofm")
      OutputFileMapCreator.write(module: "mod",
                                 inputPaths: [main],
                                 derivedData: tmpDir,
                                 to: ofm)

      try localFileSystem.writeFileContents(main, bytes:
       """
       // no errors here
       func foo() {}
       """
      )
      /// return true if no error
      func doBuild() throws -> Bool {
        let sdkArguments = try XCTUnwrap(try Driver.sdkArgumentsForTesting())
        var driver = try Driver(args: ["swiftc",
                                       "-working-directory", tmpDir.nativePathString(escaped: true),
                                       "-module-name", "mod",
                                       "-c",
                                       "-incremental",
                                       "-output-file-map", ofm.nativePathString(escaped: true),
                                       main.nativePathString(escaped: true)] + sdkArguments,
                                env: ProcessEnv.vars)
        let jobs = try driver.planBuild()
        do {try driver.run(jobs: jobs)}
        catch {return false}
        return true
      }
      XCTAssertTrue(try doBuild())

      let outputs = [
        tmpDir.appending(component: "main.o"),
        tmpDir.appending(component: "main.swiftdeps")
        ]
      XCTAssert(outputs.allSatisfy(localFileSystem.exists))

      try localFileSystem.writeFileContents(main, bytes:
        """
        #error(\"Yipes!\")
        func foo() {}
        """
      )
      XCTAssertFalse(try doBuild())
      XCTAssert(outputs.allSatisfy {!localFileSystem.exists($0)})
    }
#endif
  }

  func testCxxLinking() throws {
#if os(iOS) || os(macOS) || os(tvOS) || os(watchOS)
      throw XCTSkip("Darwin does not use clang as the linker driver")
#else
      VirtualPath.resetTemporaryFileStore()
      var driver = try Driver(args: [
        "swiftc", "-cxx-interoperability-mode=swift-5.9", "-emit-library", "-o", "library.dll", "library.obj"
      ])
      let jobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(jobs.count, 1)
      let job = jobs.first!
      XCTAssertEqual(job.kind, .link)
      XCTAssertTrue(job.tool.name.hasSuffix(executableName("clang++")))
#endif
  }

  func testEmitClangHeaderPath() throws {
      VirtualPath.resetTemporaryFileStore()
      var driver = try Driver(args: [
        "swiftc", "-emit-clang-header-path", "path/to/header", "-typecheck", "test.swift"
      ])
      let jobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(jobs.count, 2)
      let job = jobs.first!
      XCTAssertTrue(job.commandLine.contains(.flag("-emit-objc-header-path")))
      XCTAssertTrue(job.commandLine.contains(try toPathOption("path/to/header")))
  }

  func testGccToolchainFlags() throws {
      VirtualPath.resetTemporaryFileStore()
      var driver = try Driver(args: [
        "swiftc", "-gcc-toolchain", "/foo/as/blarpy", "test.swift"
      ])
      let jobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(jobs.count, 2)
      let (compileJob, linkJob) = (jobs[0], jobs[1])
      XCTAssert(compileJob.commandLine.contains(.flag("--gcc-toolchain=/foo/as/blarpy")))
      XCTAssert(linkJob.commandLine.contains(.flag("--gcc-toolchain=/foo/as/blarpy")))
  }

  func testPluginPaths() throws {
    try pluginPathTest(platform: "iPhoneOS", sdk: "iPhoneOS13.0", searchPlatform: "iPhoneOS")
    try pluginPathTest(platform: "iPhoneSimulator", sdk: "iPhoneSimulator15.0", searchPlatform: "iPhoneOS")
  }

  func pluginPathTest(platform: String, sdk: String, searchPlatform: String) throws {
    let sdkRoot = try testInputsPath.appending(
      components: ["Platform Checks", "\(platform).platform", "Developer", "SDKs", "\(sdk).sdk"])
    var driver = try Driver(args: ["swiftc", "-typecheck", "foo.swift", "-sdk", VirtualPath.absolute(sdkRoot).name, "-plugin-path", "PluginA", "-external-plugin-path", "Plugin~B#Bexe", "-load-plugin-library", "PluginB2", "-plugin-path", "PluginC", "-load-plugin-executable", "PluginD#PluginD", "-working-directory", "/tmp"])
    guard driver.isFrontendArgSupported(.pluginPath) && driver.isFrontendArgSupported(.externalPluginPath) else {
      return
    }

    let jobs = try driver.planBuild().removingAutolinkExtractJobs()
    XCTAssertEqual(jobs.count, 1)
    let job = jobs.first!

    // Check that the we have the plugin paths we expect, in the order we expect.
    let pluginAIndex = job.commandLine.firstIndex(of: .path(VirtualPath.absolute(try .init(validating: "/tmp/PluginA"))))
    XCTAssertNotNil(pluginAIndex)

    let pluginBIndex = job.commandLine.firstIndex(of: .path(VirtualPath.absolute(try .init(validating: "/tmp/Plugin~B#Bexe"))))
    XCTAssertNotNil(pluginBIndex)
    XCTAssertLessThan(pluginAIndex!, pluginBIndex!)

    let pluginB2Index = job.commandLine.firstIndex(of: .path(VirtualPath.absolute(try .init(validating: "/tmp/PluginB2"))))
    XCTAssertNotNil(pluginB2Index)
    XCTAssertLessThan(pluginBIndex!, pluginB2Index!)

    let pluginCIndex = job.commandLine.firstIndex(of: .path(VirtualPath.absolute(try .init(validating: "/tmp/PluginC"))))
    XCTAssertNotNil(pluginCIndex)
    XCTAssertLessThan(pluginB2Index!, pluginCIndex!)

    #if os(macOS)
    let origPlatformPath =
      sdkRoot.parentDirectory.parentDirectory.parentDirectory.parentDirectory
        .appending(component: "\(searchPlatform).platform")

    let platformPath = origPlatformPath.appending(components: "Developer", "usr")
    let platformServerPath = platformPath.appending(components: "bin", "swift-plugin-server").pathString

    let platformPluginPath = platformPath.appending(components: "lib", "swift", "host", "plugins")
    let platformPluginPathIndex = job.commandLine.firstIndex(of: .flag("\(platformPluginPath)#\(platformServerPath)"))
    XCTAssertNotNil(platformPluginPathIndex)

    let platformLocalPluginPath = platformPath.appending(components: "local", "lib", "swift", "host", "plugins")
    let platformLocalPluginPathIndex = job.commandLine.firstIndex(of: .flag("\(platformLocalPluginPath)#\(platformServerPath)"))
    XCTAssertNotNil(platformLocalPluginPathIndex)
    XCTAssertLessThan(platformPluginPathIndex!, platformLocalPluginPathIndex!)

    let toolchainPluginPathIndex = job.commandLine.firstIndex(of: .path(.absolute(try driver.toolchain.executableDir.parentDirectory.appending(components: "lib", "swift", "host", "plugins"))))
    XCTAssertNotNil(toolchainPluginPathIndex)

    let toolchainStdlibPath = VirtualPath.lookup(driver.frontendTargetInfo.runtimeResourcePath.path)
      .appending(components: driver.frontendTargetInfo.target.triple.platformName() ?? "", "Swift.swiftmodule")
    let hasToolchainStdlib = try driver.fileSystem.exists(toolchainStdlibPath)
    if hasToolchainStdlib {
      XCTAssertGreaterThan(platformLocalPluginPathIndex!, toolchainPluginPathIndex!)
    } else {
      XCTAssertLessThan(platformLocalPluginPathIndex!, toolchainPluginPathIndex!)
    }
    #endif

    XCTAssertTrue(job.commandLine.contains(.flag("-plugin-path")))
    XCTAssertFalse(job.commandLine.contains(.flag("-load-plugin")))
#if os(Windows)
    XCTAssertTrue(job.commandLine.contains(.path(.absolute(try driver.toolchain.executableDir.parentDirectory.appending(components: "bin")))))
#else
    XCTAssertTrue(job.commandLine.contains(.path(.absolute(try driver.toolchain.executableDir.parentDirectory.appending(components: "lib", "swift", "host", "plugins")))))
    XCTAssertTrue(job.commandLine.contains(.path(.absolute(try driver.toolchain.executableDir.parentDirectory.appending(components: "local", "lib", "swift", "host", "plugins")))))
#endif
  }

  func testWasmPlugins() throws {
    let sdkRoot = try testInputsPath.appending(
      components: ["Platform Checks", "iPhoneOS.platform", "Developer", "SDKs", "iPhoneOS13.0.sdk"])
    let executor = try SwiftDriverExecutor(
      diagnosticsEngine: DiagnosticsEngine(handlers: [Driver.stderrDiagnosticsHandler]),
      processSet: ProcessSet(),
      fileSystem: localFileSystem,
      env: [:]
    )
    let executableDir = try AbsolutePath(validating: "/tmp/swift/bin")
    var driver = try Driver(
      args: ["swiftc", "-typecheck", "foo.swift", "-sdk", VirtualPath.absolute(sdkRoot).name, "-load-plugin-executable", "PluginA#ModuleA", "-load-plugin-executable", "PluginB.wasm#ModuleB", "-working-directory", "/tmp", "-load-plugin-library", "PluginC.dylib"],
      executor: executor,
      compilerExecutableDir: executableDir
    )
    try XCTSkipUnless(driver.isFrontendArgSupported(.loadPlugin))

    let jobs = try driver.planBuild().removingAutolinkExtractJobs()
    XCTAssertEqual(jobs.count, 1)
    let job = jobs.first!

    #if os(Windows)
    let expectedWasmServerPath = executableDir.appending(component: "swift-plugin-server.exe")
    #else
    let expectedWasmServerPath = executableDir.appending(component: "swift-plugin-server")
    #endif

    // Check that the we have the plugin path
    let pluginAIndex = try XCTUnwrap(job.commandLine.firstIndex(of: .path(.absolute(AbsolutePath(validating: "/tmp/PluginA#ModuleA")))))
    let pluginBIndex = try XCTUnwrap(job.commandLine.firstIndex(of: .flag("/tmp/PluginB.wasm:\(expectedWasmServerPath)#ModuleB")))
    let pluginCIndex = try XCTUnwrap(job.commandLine.firstIndex(of: .path(.absolute(AbsolutePath(validating: "/tmp/PluginC.dylib")))))

    XCTAssertLessThan(pluginAIndex, pluginBIndex, "Order of options should be preserved")
    XCTAssertLessThan(pluginBIndex, pluginCIndex, "Order of options should be preserved")
  }

  func testClangModuleValidateOnce() throws {
    let flagTest = try Driver(args: ["swiftc", "-typecheck", "foo.swift"])
    guard flagTest.isFrontendArgSupported(.clangBuildSessionFile),
          flagTest.isFrontendArgSupported(.validateClangModulesOnce) else {
      return
    }

    do {
      var driver = try Driver(args: ["swiftc", "-typecheck", "foo.swift"])
      let jobs = try driver.planBuild().removingAutolinkExtractJobs()
      let job = jobs.first!
      XCTAssertFalse(job.commandLine.contains(.flag("-validate-clang-modules-once")))
      XCTAssertFalse(job.commandLine.contains(.flag("-clang-build-session-file")))
    }

    do {
      try assertDriverDiagnostics(args: ["swiftc", "-validate-clang-modules-once",
                                         "foo.swift"]) {
        $1.expect(.error("'-validate-clang-modules-once' cannot be specified if '-clang-build-session-file' is not present"))
      }
    }

    do {
      var driver = try Driver(args: ["swiftc", "-validate-clang-modules-once",
                                     "-clang-build-session-file", "testClangModuleValidateOnce.session",
                                     "foo.swift"])
      let jobs = try driver.planBuild().removingAutolinkExtractJobs()
      let job = jobs.first!
      XCTAssertTrue(job.commandLine.contains(.flag("-validate-clang-modules-once")))
      XCTAssertTrue(job.commandLine.contains(.flag("-clang-build-session-file")))
    }
  }

  func testRegistrarLookup() throws {
#if os(Windows)
    let SDKROOT: AbsolutePath = localFileSystem.currentWorkingDirectory!.appending(components: "SDKROOT")
    let resourceDir: AbsolutePath = localFileSystem.currentWorkingDirectory!.appending(components: "swift", "resources")

    let platform: String = "windows"
#if arch(x86_64)
    let arch: String = "x86_64"
#elseif arch(arm64)
    let arch: String = "aarch64"
#else
#error("unsupported build architecture")
#endif

    do {
      var driver = try Driver(args: [
        "swiftc", "-emit-library", "-o", "library.dll", "library.obj", "-resource-dir", resourceDir.nativePathString(escaped: false),
      ])
      let jobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(jobs.count, 1)
      let job = jobs.first!
      XCTAssertEqual(job.kind, .link)
      XCTAssertTrue(job.commandLine.contains(.path(.absolute(resourceDir.appending(component: "swiftrt.obj")))))
    }

    do {
      var driver = try Driver(args: [
        "swiftc", "-emit-library", "-o", "library.dll", "library.obj", "-sdk", SDKROOT.nativePathString(escaped: false),
      ])
      let jobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(jobs.count, 1)
      let job = jobs.first!
      XCTAssertEqual(job.kind, .link)
      XCTAssertTrue(job.commandLine.contains(.path(.absolute(SDKROOT.appending(components: "usr", "lib", "swift", platform, arch, "swiftrt.obj")))))
    }

    do {
      var env = ProcessEnv.vars
      env["SDKROOT"] = SDKROOT.nativePathString(escaped: false)

      var driver = try Driver(args: [
        "swiftc", "-emit-library", "-o", "library.dll", "library.obj"
      ], env: env)
      let jobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(jobs.count, 1)
      let job = jobs.first!
      XCTAssertEqual(job.kind, .link)
      XCTAssertTrue(job.commandLine.contains(.path(.absolute(SDKROOT.appending(components: "usr", "lib", "swift", platform, arch, "swiftrt.obj")))))
    }

    do {
      var env = ProcessEnv.vars
      env["SDKROOT"] = SDKROOT.nativePathString(escaped: false)

      var driver = try Driver(args: [
        "swiftc", "-emit-library", "-o", "library.dll", "library.obj", "-nostartfiles",
      ], env: env)
      let jobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(jobs.count, 1)
      let job = jobs.first!
      XCTAssertEqual(job.kind, .link)
      XCTAssertFalse(job.commandLine.contains(.path(.absolute(SDKROOT.appending(components: "usr", "lib", "swift", platform, arch, "swiftrt.obj")))))
    }

    // Cannot test this due to `SDKROOT` escaping from the execution environment
    // into the `-print-target-info` step, which then resets the
    // `runtimeResourcePath` to be the SDK relative path rahter than the
    // toolchain relative path.
#if false
    do {
      var env = ProcessEnv.vars
      env["SDKROOT"] = nil

      var driver = try Driver(args: [
        "swiftc", "-emit-library", "-o", "library.dll", "library.obj"
      ], env: env)
      driver.frontendTargetInfo.runtimeResourcePath = SDKROOT
      let jobs = try driver.planBuild().removingAutolinkExtractJobs()
      XCTAssertEqual(jobs.count, 1)
      let job = jobs.first!
      XCTAssertEqual(job.kind, .link)
      XCTAssertTrue(job.commandLine.contains(.path(.absolute(SDKROOT.appending(components: "usr", "lib", "swift", platform, arch, "swiftrt.obj")))))
    }
#endif
#endif
  }

  func testFindingBlockLists() throws {
    let execDir = try testInputsPath.appending(components: "Dummy.xctoolchain", "usr", "bin")
    let list = try Driver.findBlocklists(RelativeTo: execDir)
    XCTAssertEqual(list.count, 2)
    XCTAssertTrue(list.allSatisfy { $0.extension! == "yml" || $0.extension! == "yaml"})
  }

  func testFindingBlockListVersion() throws {
    let execDir = try testInputsPath.appending(components: "Dummy.xctoolchain", "usr", "bin")
    let version = try Driver.findCompilerClientsConfigVersion(RelativeTo: execDir)
    XCTAssertEqual(version, "compilerClientsConfig-9999.99.9")
  }

  func testToolSearching() throws {
#if os(Windows)
    let PATH = "Path"
#else
    let PATH = "PATH"
#endif
    let SWIFT_FRONTEND_EXEC = "SWIFT_DRIVER_SWIFT_FRONTEND_EXEC"
    let SWIFT_SCANNER_LIB = "SWIFT_DRIVER_SWIFTSCAN_LIB"


    // Reset the environment to ensure tool resolution is exactly run against PATH.
    var driver = try Driver(args: ["swiftc", "-print-target-info"], env: [PATH: ProcessEnv.path!])
    let jobs = try driver.planBuild()
    XCTAssertEqual(jobs.count, 1)
    let defaultSwiftFrontend = jobs.first!.tool.absolutePath!
    let originalWorkingDirectory = localFileSystem.currentWorkingDirectory!

    try withTemporaryDirectory { toolsDirectory in
      let customSwiftFrontend = toolsDirectory.appending(component: executableName("swift-frontend"))
      let customSwiftScan = toolsDirectory.appending(component: sharedLibraryName("lib_InternalSwiftScan"))
      try localFileSystem.createSymbolicLink(customSwiftFrontend, pointingAt: defaultSwiftFrontend, relative: false)

      try withTemporaryDirectory { tempDirectory in
        try localFileSystem.changeCurrentWorkingDirectory(to: tempDirectory)
        defer { try! localFileSystem.changeCurrentWorkingDirectory(to: originalWorkingDirectory) }

        let anotherSwiftFrontend = localFileSystem.currentWorkingDirectory!.appending(component: executableName("swift-frontend"))
        try localFileSystem.createSymbolicLink(anotherSwiftFrontend, pointingAt: defaultSwiftFrontend, relative: false)

        // test if SWIFT_DRIVER_TOOLNAME_EXEC is respected
        do {
          var driver = try Driver(args: ["swiftc", "-print-target-info"],
                                  env: [PATH: ProcessEnv.path!,
                                        SWIFT_FRONTEND_EXEC: customSwiftFrontend.pathString,
                                        SWIFT_SCANNER_LIB: customSwiftScan.pathString])
          let jobs = try driver.planBuild()
          XCTAssertEqual(jobs.count, 1)
          XCTAssertEqual(jobs.first!.tool.name, customSwiftFrontend.pathString)
        }

        // test if tools directory is respected
        do {
          var driver = try Driver(args: ["swiftc", "-print-target-info", "-tools-directory", toolsDirectory.pathString],
                                  env: [PATH: ProcessEnv.path!, SWIFT_SCANNER_LIB: customSwiftScan.pathString])
          let jobs = try driver.planBuild()
          XCTAssertEqual(jobs.count, 1)
          XCTAssertEqual(jobs.first!.tool.name, customSwiftFrontend.pathString)
        }

        // test if current working directory is searched before PATH
        do {
          var driver = try Driver(args: ["swiftc", "-print-target-info"],
                                  env: [PATH: toolsDirectory.pathString, SWIFT_SCANNER_LIB: customSwiftScan.pathString])
          let jobs = try driver.planBuild()
          XCTAssertEqual(jobs.count, 1)
          XCTAssertEqual(jobs.first!.tool.name, anotherSwiftFrontend.pathString)
        }
      }
    }
  }

  func testWindowsOptions() throws {
    let driver =
        try Driver(args: ["swiftc", "-windows-sdk-version", "10.0.17763.0", #file])
    guard [
            .visualcToolsRoot,
            .visualcToolsVersion,
            .windowsSdkRoot,
            .windowsSdkVersion
          ].map(driver.isFrontendArgSupported).reduce(true, { $0 && $1 }) else {
      return
    }

    do {
      var driver = try Driver(args: [
        "swiftc", "-target", "x86_64-unknown-windows-msvc", "-windows-sdk-root", "/SDK", #file
      ])
      let frontend = try driver.planBuild().first!

      XCTAssertTrue(frontend.commandLine.contains(subsequence: [
        .flag("-windows-sdk-root"),
        .path(.absolute(try .init(validating: "/SDK")))
      ]))
    }

    do {
      var driver = try Driver(args: [
        "swiftc", "-target", "x86_64-unknown-windows-msvc", "-windows-sdk-version", "10.0.17763.0", #file
      ])
      let frontend = try driver.planBuild().first!

      XCTAssertTrue(frontend.commandLine.contains(subsequence: [
        .flag("-windows-sdk-version"),
        .flag("10.0.17763.0")
      ]))
    }

    do {
      var driver = try Driver(args: [
        "swiftc", "-target", "x86_64-unknown-windows-msvc", "-windows-sdk-version", "10.0.17763.0", "-windows-sdk-root", "/SDK", #file
      ])
      let frontend = try driver.planBuild().first!

      XCTAssertTrue(frontend.commandLine.contains(subsequence: [
        .flag("-windows-sdk-root"),
        .path(.absolute(try .init(validating: "/SDK")))
      ]))
      XCTAssertTrue(frontend.commandLine.contains(subsequence: [
        .flag("-windows-sdk-version"),
        .flag("10.0.17763.0")
      ]))
    }

    do {
      var driver = try Driver(args: [
        "swiftc", "-target", "x86_64-unknown-windows-msvc", "-visualc-tools-root", "/MSVC/14.34.31933", #file
      ])
      let frontend = try driver.planBuild().first!

      XCTAssertTrue(frontend.commandLine.contains(subsequence: [
        .flag("-visualc-tools-root"),
        .path(.absolute(try .init(validating: "/MSVC/14.34.31933"))),
      ]))
    }

    do {
      var driver = try Driver(args: [
        "swiftc", "-target", "x86_64-unknown-windows-msvc", "-visualc-tools-version", "14.34.31933", #file
      ])
      let frontend = try driver.planBuild().first!

      XCTAssertTrue(frontend.commandLine.contains(subsequence: [
        .flag("-visualc-tools-version"),
        .flag("14.34.31933")
      ]))
    }

    do {
      var driver = try Driver(args: [
        "swiftc", "-target", "x86_64-unknown-windows-msvc", "-visualc-tools-root", "/MSVC", "-visualc-tools-version", "14.34.31933", #file
      ])
      let frontend = try driver.planBuild().first!

      XCTAssertTrue(frontend.commandLine.contains(subsequence: [
        .flag("-visualc-tools-version"),
        .flag("14.34.31933")
      ]))
      XCTAssertTrue(frontend.commandLine.contains(subsequence: [
        .flag("-visualc-tools-root"),
        .path(.absolute(try .init(validating: "/MSVC"))),
      ]))
    }
  }
  
  func testEmitAPIDescriptorEmitModule() throws {
    try withTemporaryDirectory { path in
      do {
        let apiDescriptorPath = path.appending(component: "api.json").nativePathString(escaped: true)
        var driver = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "baz.swift",
                                       "-emit-module", "-module-name", "Test",
                                       "-emit-api-descriptor-path", apiDescriptorPath])

        let jobs = try driver.planBuild().removingAutolinkExtractJobs()
        let emitModuleJob = try jobs.findJob(.emitModule)
        XCTAssert(emitModuleJob.commandLine.contains(.flag("-emit-api-descriptor-path")))
      }

      do {
        var env = ProcessEnv.vars
        env["TAPI_SDKDB_OUTPUT_PATH"] = path.appending(component: "SDKDB").nativePathString(escaped: false)
        var driver = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "baz.swift",
                                       "-emit-module", "-module-name", "Test"], env: env)
        let jobs = try driver.planBuild().removingAutolinkExtractJobs()
        let emitModuleJob = try jobs.findJob(.emitModule)
        XCTAssert(emitModuleJob.commandLine.contains(subsequence: [
          .flag("-emit-api-descriptor-path"),
          .path(.absolute(path.appending(components: "SDKDB", "Test.\(driver.frontendTargetInfo.target.moduleTriple.triple).swift.sdkdb"))),
        ]))
      }

      do {
        var env = ProcessEnv.vars
        env["LD_TRACE_FILE"] = path.appending(component: ".LD_TRACE").nativePathString(escaped: false)
        var driver = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "baz.swift",
                                       "-emit-module", "-module-name", "Test"], env: env)
        let jobs = try driver.planBuild().removingAutolinkExtractJobs()
        let emitModuleJob = try jobs.findJob(.emitModule)
        XCTAssert(emitModuleJob.commandLine.contains(subsequence: [
          .flag("-emit-api-descriptor-path"),
          .path(.absolute(path.appending(components: "SDKDB", "Test.\(driver.frontendTargetInfo.target.moduleTriple.triple).swift.sdkdb"))),
        ]))
      }
    }
  }

  func testEmitAPIDescriptorWholeModuleOptimization() throws {
    try withTemporaryDirectory { path in
      do {
        let apiDescriptorPath = path.appending(component: "api.json").nativePathString(escaped: true)
        var driver = try Driver(args: ["swiftc", "-whole-module-optimization",
                                       "-driver-filelist-threshold=0",
                                       "foo.swift", "bar.swift", "baz.swift",
                                       "-module-name", "Test", "-emit-module",
                                       "-emit-api-descriptor-path", apiDescriptorPath])

        let jobs = try driver.planBuild().removingAutolinkExtractJobs()
        let compileJob = try jobs.findJob(.compile)
        let supplementaryOutputs = try XCTUnwrap(compileJob.commandLine.supplementaryOutputFilemap)
        XCTAssertNotNil(supplementaryOutputs.entries.values.first?[.jsonAPIDescriptor])
      }

      do {
        var env = ProcessEnv.vars
        env["TAPI_SDKDB_OUTPUT_PATH"] = path.appending(component: "SDKDB").nativePathString(escaped: false)
        var driver = try Driver(args: ["swiftc", "-whole-module-optimization",
                                       "-driver-filelist-threshold=0",
                                       "foo.swift", "bar.swift", "baz.swift",
                                       "-module-name", "Test", "-emit-module"], env: env)

        let jobs = try driver.planBuild().removingAutolinkExtractJobs()
        let compileJob = try jobs.findJob(.compile)
        let supplementaryOutputs = try XCTUnwrap(compileJob.commandLine.supplementaryOutputFilemap)
        XCTAssertNotNil(supplementaryOutputs.entries.values.first?[.jsonAPIDescriptor])
      }

      do {
        var env = ProcessEnv.vars
        env["LD_TRACE_FILE"] = path.appending(component: ".LD_TRACE").nativePathString(escaped: false)
        var driver = try Driver(args: ["swiftc", "-whole-module-optimization",
                                       "-driver-filelist-threshold=0",
                                       "foo.swift", "bar.swift", "baz.swift",
                                       "-module-name", "Test", "-emit-module"], env: env)

        let jobs = try driver.planBuild().removingAutolinkExtractJobs()
        let compileJob = try jobs.findJob(.compile)
        let supplementaryOutputs = try XCTUnwrap(compileJob.commandLine.supplementaryOutputFilemap)
        XCTAssertNotNil(supplementaryOutputs.entries.values.first?[.jsonAPIDescriptor])
      }
    }
  }

  func testCachingBuildOptions() throws {
    try assertDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module", "-cache-compile-job") {
      $1.expect(.warning("-cache-compile-job cannot be used without explicit module build, turn off caching"))
    }
    try assertNoDriverDiagnostics(args: "swiftc", "foo.swift", "-emit-module", "-cache-compile-job", "-explicit-module-build")
  }
}

func assertString(
  _ haystack: String, contains needle: String, _ message: String = "",
  file: StaticString = #file, line: UInt = #line
) {
  XCTAssertTrue(haystack.contains(needle), """
                \(String(reflecting: needle)) not found in \
                \(String(reflecting: haystack))\
                \(message.isEmpty ? "" : ": " + message)
                """, file: file, line: line)
}

extension Array where Element: Equatable {
  /// Returns true if the receiver contains the given elements as a subsequence
  /// (i.e., all elements are present, contiguous, and in the same order).
  ///
  /// A naïve implementation has been used here rather than a more efficient
  /// general purpose substring search algorithm since the arrays being tested
  /// are relatively small.
  func contains<Elements: Collection>(
    subsequence: Elements
  ) -> Bool
  where Elements.Element == Element
  {
    precondition(!subsequence.isEmpty,  "Subsequence may not be empty")

    let subsequenceCount = subsequence.count
    for index in 0...(self.count - subsequence.count) {
      let subsequenceEnd = index + subsequenceCount
      if self[index..<subsequenceEnd].elementsEqual(subsequence) {
        return true
      }
    }
    return false
  }
}

extension Array where Element == Job {
  /// Utility to drop autolink-extract jobs, which helps avoid introducing
  /// platform-specific conditionals in tests unrelated to autolinking.
  func removingAutolinkExtractJobs() -> Self {
    var filtered = self
    filtered.removeAll(where: { $0.kind == .autolinkExtract })
    return filtered
  }

  /// Returns true if a job with the given Kind is contained in the array.
  func containsJob(_ kind: Job.Kind) -> Bool {
    return contains(where: { $0.kind == kind })
  }

  /// Finds the first job with the given kind, or throws if one cannot be found.
  func findJob(_ kind: Job.Kind) throws -> Job {
    return try XCTUnwrap(first(where: { $0.kind == kind }))
  }
}

private extension Array where Element == Job.ArgTemplate {
  func containsPathWithBasename(_ basename: String) -> Bool {
    contains {
      switch $0 {
      case let .path(path):
        return path.basename == basename
      case .flag, .responseFilePath, .joinedOptionAndPath, .squashedArgumentList:
        return false
      }
    }
  }

  var supplementaryOutputFilemap: OutputFileMap? {
    get throws {
      guard let argIdx = firstIndex(where: { $0 == .flag("-supplementary-output-file-map") }) else {
        return nil
      }
      let supplementaryOutputs = self[argIdx + 1]
      guard case let .path(path) = supplementaryOutputs,
            case let .fileList(_, fileList) = path,
            case let .outputFileMap(outputFileMap) = fileList else {
        throw StringError("Unexpected argument for output file map")
      }
      return outputFileMap
    }
  }
}
