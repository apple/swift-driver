import XCTest
import SwiftDriver
import TSCBasic

final class SwiftDriverTests: XCTestCase {
    func testParsing() throws {
      // Form an options table
      let options = OptionTable()
      // Parse each kind of option
      let results = try options.parse([
        "input1", "-color-diagnostics", "-Ifoo", "-I", "bar spaces",
        "-I=wibble", "input2", "-module-name", "main",
        "-sanitize=a,b,c", "--", "-foo", "-bar"])
      XCTAssertEqual(results.description,
                     "input1 -color-diagnostics -I foo -I 'bar spaces' -I=wibble input2 -module-name main -sanitize=a,b,c -- -foo -bar")
    }

  func testParseErrors() {
    let options = OptionTable()

    // FIXME: Check for the exact form of the error
    XCTAssertThrowsError(try options.parse(["-unrecognized"]))
    XCTAssertThrowsError(try options.parse(["-I"]))
    XCTAssertThrowsError(try options.parse(["-module-name"]))
  }

  func testDriverKindParsing() throws {
    XCTAssertEqual(try Driver.determineDriverKind(args: ["swift"]), .interactive)
    XCTAssertEqual(try Driver.determineDriverKind(args: ["/path/to/swift"]), .interactive)
    XCTAssertEqual(try Driver.determineDriverKind(args: ["swiftc"]), .batch)
    XCTAssertEqual(try Driver.determineDriverKind(args: [".build/debug/swiftc"]), .batch)
    XCTAssertEqual(try Driver.determineDriverKind(args: ["swiftc", "-frontend"]), .frontend)
    XCTAssertEqual(try Driver.determineDriverKind(args: ["swiftc", "-modulewrap"]), .moduleWrap)
    XCTAssertEqual(try Driver.determineDriverKind(args: ["/path/to/swiftc", "-modulewrap"]), .moduleWrap)

    XCTAssertEqual(try Driver.determineDriverKind(args: ["swiftc", "--driver-mode=swift"]), .interactive)
    XCTAssertEqual(try Driver.determineDriverKind(args: ["swiftc", "--driver-mode=swift-autolink-extract"]), .autolinkExtract)
    XCTAssertEqual(try Driver.determineDriverKind(args: ["swiftc", "--driver-mode=swift-indent"]), .indent)
    XCTAssertEqual(try Driver.determineDriverKind(args: ["swift", "--driver-mode=swift-autolink-extract"]), .autolinkExtract)

    XCTAssertThrowsError(try Driver.determineDriverKind(args: ["driver"]))
    XCTAssertThrowsError(try Driver.determineDriverKind(args: ["swiftc", "--driver-mode=blah"]))
    XCTAssertThrowsError(try Driver.determineDriverKind(args: ["swiftc", "--driver-mode="]))
  }

  func testCompilerMode() throws {
    do {
      let driver1 = try Driver(args: ["swift", "main.swift"])
      XCTAssertEqual(driver1.compilerMode, .immediate)

      let driver2 = try Driver(args: ["swift"])
      XCTAssertEqual(driver2.compilerMode, .repl)
    }

    do {
      let driver1 = try Driver(args: ["swiftc", "main.swift", "-whole-module-optimization"])
      XCTAssertEqual(driver1.compilerMode, .singleCompile)

      let driver2 = try Driver(args: ["swiftc", "main.swift", "-g"])
      XCTAssertEqual(driver2.compilerMode, .standardCompile)
    }
  }

  func testInputFiles() throws {
    let driver1 = try Driver(args: ["swift", "a.swift", "/tmp/b.swift"])
    XCTAssertEqual(driver1.inputFiles,
                   [ InputFile(file: .relative(RelativePath("a.swift")), type: .swift),
                     InputFile(file: .absolute(AbsolutePath("/tmp/b.swift")), type: .swift) ])
    let driver2 = try Driver(args: ["swift", "a.swift", "-working-directory", "/wobble", "/tmp/b.swift"])
    XCTAssertEqual(driver2.inputFiles,
                   [ InputFile(file: .absolute(AbsolutePath("/wobble/a.swift")), type: .swift),
                     InputFile(file: .absolute(AbsolutePath("/tmp/b.swift")), type: .swift) ])

    let driver3 = try Driver(args: ["swift", "-"])
    XCTAssertEqual(driver3.inputFiles, [ InputFile(file: .standardInput, type: .swift )])

    let driver4 = try Driver(args: ["swift", "-", "-working-directory" , "-wobble"])
    XCTAssertEqual(driver4.inputFiles, [ InputFile(file: .standardInput, type: .swift )])
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
  }

  func testDebugSettings() throws {
    let driver1 = try Driver(args: ["swiftc", "foo.swift", "-emit-module"])
    XCTAssertNil(driver1.debugInfoLevel)
    XCTAssertEqual(driver1.debugInfoFormat, .dwarf)

    let driver2 = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-g"])
    XCTAssertEqual(driver2.debugInfoLevel, .astTypes)
    XCTAssertEqual(driver2.debugInfoFormat, .dwarf)

    let driver3 = try Driver(args: ["swiftc", "-g", "foo.swift", "-gline-tables-only"])
    XCTAssertEqual(driver3.debugInfoLevel, .lineTables)
    XCTAssertEqual(driver3.debugInfoFormat, .dwarf)

    let driver4 = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-g", "-debug-info-format=codeview"])
    XCTAssertEqual(driver4.debugInfoLevel, .astTypes)
    XCTAssertEqual(driver4.debugInfoFormat, .codeView)

    let driver5 = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-debug-info-format=dwarf"])
    XCTAssertEqual(driver5.diagnosticEngine.diagnostics.map{$0.localizedDescription}, ["option '-debug-info-format=' is missing a required argument (-g)"])

    let driver6 = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-g", "-debug-info-format=notdwarf"])
    XCTAssertEqual(driver6.diagnosticEngine.diagnostics.map{$0.localizedDescription}, ["invalid value 'notdwarf' in '-debug-info-format='"])

    let driver7 = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-gdwarf-types", "-debug-info-format=codeview"])
    XCTAssertEqual(driver7.diagnosticEngine.diagnostics.map{$0.localizedDescription}, ["argument 'codeview' is not allowed with '-gdwarf-types'"])
  }

  func testModuleSettings() throws {
    let driver1 = try Driver(args: ["swiftc", "foo.swift"])
    XCTAssertNil(driver1.moduleOutput)
    XCTAssertEqual(driver1.moduleName, "foo")

    let driver2 = try Driver(args: ["swiftc", "foo.swift", "-g"])
    XCTAssertEqual(driver2.moduleOutput, ModuleOutput.auxiliary(VirtualPath.temporary("foo.swiftmodule")))
    XCTAssertEqual(driver2.moduleName, "foo")

    let driver3 = try Driver(args: ["swiftc", "foo.swift", "-module-name", "wibble", "bar.swift", "-g"])
    XCTAssertEqual(driver3.moduleOutput, ModuleOutput.auxiliary( VirtualPath.temporary("wibble.swiftmodule")))
    XCTAssertEqual(driver3.moduleName, "wibble")

    let driver4 = try Driver(args: ["swiftc", "-emit-module", "foo.swift", "-module-name", "wibble", "bar.swift"])
    XCTAssertEqual(driver4.moduleOutput, ModuleOutput.topLevel(try VirtualPath(path: "wibble.swiftmodule")))
    XCTAssertEqual(driver4.moduleName, "wibble")

    let driver5 = try Driver(args: ["swiftc", "foo.swift", "bar.swift"])
    XCTAssertNil(driver5.moduleOutput)
    XCTAssertEqual(driver5.moduleName, "main")

    let driver6 = try Driver(args: ["swiftc", "-repl"])
    XCTAssertNil(driver6.moduleOutput)
    XCTAssertEqual(driver6.moduleName, "REPL")

    let driver7 = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-emit-library", "-o", "libWibble.so"])
    XCTAssertEqual(driver7.moduleName, "Wibble")

    let driver8 = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-emit-library", "-o", "libWibble.so", "-module-name", "Swift"])
    XCTAssertEqual(driver8.diagnosticEngine.diagnostics.map{$0.localizedDescription}, ["module name \"Swift\" is reserved for the standard library"])
  }

  func testStandardCompileJobs() throws {
    var driver1 = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-module-name", "Test"])
    let plannedJobs = try driver1.planBuild()
    XCTAssertEqual(plannedJobs.count, 3)
    XCTAssertEqual(plannedJobs[0].outputs.count, 6)
    XCTAssertEqual(plannedJobs[0].outputs.first!, VirtualPath.temporary("foo.o"))
    XCTAssertEqual(plannedJobs[1].outputs.count, 6)
    XCTAssertEqual(plannedJobs[1].outputs.first!, VirtualPath.temporary("bar.o"))
    XCTAssertTrue(plannedJobs[2].tool.name.contains("ld"))
    XCTAssertEqual(plannedJobs[2].outputs.count, 1)
    XCTAssertEqual(plannedJobs[2].outputs.first!, VirtualPath.relative(RelativePath("Test")))

    // Forwarding of arguments.
    var driver2 = try Driver(args: ["swiftc", "-color-diagnostics", "foo.swift", "bar.swift", "-working-directory", "/tmp", "-api-diff-data-file", "diff.txt", "-Xfrontend", "-HI", "-no-color-diagnostics", "-target", "x64_64-apple-macosx10.14", "-g"])
    let plannedJobs2 = try driver2.planBuild()
    XCTAssert(plannedJobs2[0].commandLine.contains(Job.ArgTemplate.path(.absolute(try AbsolutePath(validating: "/tmp/diff.txt")))))
    XCTAssert(plannedJobs2[0].commandLine.contains(.flag("-HI")))
    XCTAssert(!plannedJobs2[0].commandLine.contains(.flag("-Xfrontend")))
    XCTAssert(plannedJobs2[0].commandLine.contains(.flag("-no-color-diagnostics")))
    XCTAssert(!plannedJobs2[0].commandLine.contains(.flag("-color-diagnostics")))
    XCTAssert(plannedJobs2[0].commandLine.contains(.flag("-target")))
    XCTAssert(plannedJobs2[0].commandLine.contains(.flag("x64_64-apple-macosx10.14")))
    XCTAssert(plannedJobs2[0].commandLine.contains(.flag("-enable-anonymous-context-mangled-names")))

    var driver3 = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-emit-library", "-module-name", "Test"])
    let plannedJobs3 = try driver3.planBuild()
    XCTAssertTrue(plannedJobs3[0].commandLine.contains(.flag("-module-name")))
    XCTAssertTrue(plannedJobs3[0].commandLine.contains(.flag("Test")))
    XCTAssertTrue(plannedJobs3[0].commandLine.contains(.flag("-parse-as-library")))
  }

  func testOutputFileMapLoading() throws {
    let contents = """
    {
      "": {
        "swift-dependencies": "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/master.swiftdeps"
      },
      "/tmp/foo/Sources/foo/foo.swift": {
        "dependencies": "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.d",
        "object": "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.swift.o",
        "swiftmodule": "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo~partial.swiftmodule",
        "swift-dependencies": "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.swiftdeps"
      }
    }
    """

    try withTemporaryFile { file in
      let diags = DiagnosticsEngine()
      try localFileSystem.writeFileContents(file.path) { $0 <<< contents }
      let outputFileMap = try OutputFileMap.load(file: file.path, diagnosticEngine: diags)

      let object = try outputFileMap.getOutput(inputFile: .init(path: "/tmp/foo/Sources/foo/foo.swift"), outputType: .object)
      XCTAssertEqual(object.name, "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.swift.o")

      let masterDeps = try outputFileMap.getOutput(inputFile: .init(path: ""), outputType: .swiftDeps)
      XCTAssertEqual(masterDeps.name, "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/master.swiftdeps")

      XCTAssertTrue(!diags.hasErrors, "\(diags.diagnostics)")
    }
  }

  func testResponseFileExpansion() throws {
    try withTemporaryFile { file in
      try localFileSystem.writeFileContents(file.path) {
        $0 <<< "hello\nbye\nbye"
      }
      let args = try Driver.expandResponseFiles(["swift", "compiler", "-Xlinker", "@loader_path", "@" + file.path.pathString, "something"])
      XCTAssertEqual(args, ["swift", "compiler", "-Xlinker", "@loader_path", "hello", "bye", "bye", "something"])
    }
  }
}
