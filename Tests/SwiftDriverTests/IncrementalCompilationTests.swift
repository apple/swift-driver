//===--------------- IncrementalCompilationTests.swift - Swift Testing ----===//
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

@_spi(Testing) import SwiftDriver
import SwiftOptions
import TestUtilities

// MARK: - Baseline: nonincremental
final class NonincrementalCompilationTests: XCTestCase {
  func testBuildRecordReading() throws {
    let buildRecord = try XCTUnwrap(
      BuildRecord(contents: Inputs.buildRecord,
                                  failedToReadOutOfDateMap: {XCTFail($0 ?? "Failed to read map")}))
    XCTAssertEqual(buildRecord.swiftVersion,
                   "Apple Swift version 5.1 (swiftlang-1100.0.270.13 clang-1100.0.33.7)")
    XCTAssertEqual(buildRecord.argsHash, "abbbfbcaf36b93e58efaadd8271ff142")

    try XCTAssertEqual(buildRecord.buildTime,
                       Date(legacyDriverSecsAndNanos: [1570318779, 32358000]))
    try XCTAssertEqual(buildRecord.inputInfos,
                       [
                        VirtualPath.intern(path: "/Volumes/AS/repos/swift-driver/sandbox/sandbox/sandbox/file2.swift"):
                          InputInfo(status: .needsCascadingBuild,
                                    previousModTime: Date(legacyDriverSecsAndNanos: [1570318778, 0])),
                        VirtualPath.intern(path: "/Volumes/AS/repos/swift-driver/sandbox/sandbox/sandbox/main.swift"):
                          InputInfo(status: .upToDate,
                                    previousModTime: Date(legacyDriverSecsAndNanos: [1570083660, 0])),
                        VirtualPath.intern(path: "/Volumes/gazorp.swift"):
                          InputInfo(status: .needsNonCascadingBuild,
                                    previousModTime:  Date(legacyDriverSecsAndNanos: [0, 0]))
                       ])
  }

  func testBuildRecordWithoutOptionsReading() throws {
    let buildRecord = try XCTUnwrap(
      BuildRecord(
        contents: Inputs.buildRecordWithoutOptions,
        failedToReadOutOfDateMap: {XCTFail($0 ?? "Failed to read map")}))
    XCTAssertEqual(buildRecord.swiftVersion,
                   "Apple Swift version 5.1 (swiftlang-1100.0.270.13 clang-1100.0.33.7)")
    XCTAssertEqual(buildRecord.argsHash, nil)

    try XCTAssertEqual(buildRecord.buildTime,
                       Date(legacyDriverSecsAndNanos: [1570318779, 32358000]))
    try XCTAssertEqual(buildRecord.inputInfos,
                       [
                        VirtualPath.intern(path: "/Volumes/AS/repos/swift-driver/sandbox/sandbox/sandbox/file2.swift"):
                          InputInfo(status: .needsCascadingBuild,
                                    previousModTime: Date(legacyDriverSecsAndNanos: [1570318778, 0])),
                        VirtualPath.intern(path: "/Volumes/AS/repos/swift-driver/sandbox/sandbox/sandbox/main.swift"):
                          InputInfo(status: .upToDate,
                                    previousModTime: Date(legacyDriverSecsAndNanos: [1570083660, 0])),
                        VirtualPath.intern(path: "/Volumes/gazorp.swift"):
                          InputInfo(status: .needsNonCascadingBuild,
                                    previousModTime:  Date(legacyDriverSecsAndNanos: [0, 0]))
                       ])
  }

  func testReadBinarySourceFileDependencyGraph() throws {
    let absolutePath = try XCTUnwrap(Fixture.fixturePath(at: RelativePath("Incremental"),
                                                         for: "main.swiftdeps"))
    let dependencySource = DependencySource(VirtualPath.absolute(absolutePath).intern())!
    let graph = try XCTUnwrap(
      try SourceFileDependencyGraph(
        contentsOf: dependencySource,
        on: localFileSystem))
    XCTAssertEqual(graph.majorVersion, 1)
    XCTAssertEqual(graph.minorVersion, 0)
    XCTAssertEqual(graph.compilerVersionString, "Swift version 5.3-dev (LLVM f516ac602c, Swift c39f31febd)")
    graph.verify()
    var saw0 = false
    var saw1 = false
    var saw2 = false
    graph.forEachNode { node in
      switch (node.sequenceNumber, node.key.designator) {
      case let (0, .sourceFileProvide(name: name)):
        saw0 = true
        XCTAssertEqual(node.key.aspect, .interface)
        XCTAssertEqual(name, "main.swiftdeps")
        XCTAssertEqual(node.fingerprint, "ec443bb982c3a06a433bdd47b85eeba2")
        XCTAssertEqual(node.defsIDependUpon, [2])
        XCTAssertTrue(node.isProvides)
      case let (1, .sourceFileProvide(name: name)):
        saw1 = true
        XCTAssertEqual(node.key.aspect, .implementation)
        XCTAssertEqual(name, "main.swiftdeps")
        XCTAssertEqual(node.fingerprint, "ec443bb982c3a06a433bdd47b85eeba2")
        XCTAssertEqual(node.defsIDependUpon, [])
        XCTAssertTrue(node.isProvides)
      case let (2, .topLevel(name: name)):
        saw2 = true
        XCTAssertEqual(node.key.aspect, .interface)
        XCTAssertEqual(name, "a")
        XCTAssertNil(node.fingerprint)
        XCTAssertEqual(node.defsIDependUpon, [])
        XCTAssertFalse(node.isProvides)
      default:
        XCTFail()
      }
    }
    XCTAssertTrue(saw0)
    XCTAssertTrue(saw1)
    XCTAssertTrue(saw2)
  }

  func testReadComplexSourceFileDependencyGraph() throws {
    let absolutePath = try XCTUnwrap(Fixture.fixturePath(at: RelativePath("Incremental"),
                                                         for: "hello.swiftdeps"))
    let graph = try XCTUnwrap(
      try SourceFileDependencyGraph(
        contentsOf: DependencySource(VirtualPath.absolute(absolutePath).intern())!,
        on: localFileSystem))
    XCTAssertEqual(graph.majorVersion, 1)
    XCTAssertEqual(graph.minorVersion, 0)
    XCTAssertEqual(graph.compilerVersionString, "Swift version 5.3-dev (LLVM 4510748e505acd4, Swift 9f07d884c97eaf4)")
    graph.verify()

    // Check that a node chosen at random appears as expected.
    var foundNode = false
    graph.forEachNode { node in
      if case let .member(context: context, name: name) = node.key.designator,
         node.sequenceNumber == 25
      {
        XCTAssertFalse(foundNode)
        foundNode = true
        XCTAssertEqual(node.key.aspect, .interface)
        XCTAssertEqual(context, "5hello1BV")
        XCTAssertEqual(name, "init")
        XCTAssertEqual(node.defsIDependUpon, [])
        XCTAssertFalse(node.isProvides)
      }
    }
    XCTAssertTrue(foundNode)
    
    // Check that an edge chosen at random appears as expected.
    var foundEdge = false
    graph.forEachArc { defNode, useNode in
      if defNode.sequenceNumber == 0 && useNode.sequenceNumber == 10 {
        switch (defNode.key.designator, useNode.key.designator) {
        case let (.sourceFileProvide(name: defName),
                  .potentialMember(context: useContext)):
          XCTAssertFalse(foundEdge)
          foundEdge = true

          XCTAssertEqual(defName, "/Users/owenvoorhees/Desktop/hello.swiftdeps")
          XCTAssertEqual(defNode.fingerprint, "38b457b424090ac2e595be0e5f7e3b5b")

          XCTAssertEqual(useContext, "5hello1AC")
          XCTAssertEqual(useNode.fingerprint, "b83bbc0b4b0432dbfabff6556a3a901f")

        default:
          XCTFail()
        }
      }
    }
    XCTAssertTrue(foundEdge)
  }

  func testExtractSourceFileDependencyGraphFromSwiftModule() throws {
    let absolutePath = try XCTUnwrap(Fixture.fixturePath(at: RelativePath("Incremental"),
                                                         for: "hello.swiftmodule"))
    let data = try localFileSystem.readFileContents(absolutePath)
    let graph = try XCTUnwrap(
      try SourceFileDependencyGraph(data: data,
                                    from: DependencySource(VirtualPath.absolute(absolutePath).intern())!,
                                    fromSwiftModule: true))
    XCTAssertEqual(graph.majorVersion, 1)
    XCTAssertEqual(graph.minorVersion, 0)
    XCTAssertEqual(graph.compilerVersionString, "Apple Swift version 5.3-dev (LLVM 240312aa7333e90, Swift 15bf0478ad7c47c)")
    graph.verify()

    // Check that a node chosen at random appears as expected.
    var foundNode = false
    graph.forEachNode { node in
      if case .nominal(context: "5hello3FooV") = node.key.designator,
         node.sequenceNumber == 4
      {
        XCTAssertFalse(foundNode)
        foundNode = true
        XCTAssertEqual(node.key.aspect, .interface)
        XCTAssertEqual(node.defsIDependUpon, [0])
        XCTAssertTrue(node.isProvides)
      }
    }
    XCTAssertTrue(foundNode)
  }

  func testDateConversion() {
    let sn =  [0, 8000]
    let d = try! Date(legacyDriverSecsAndNanos: sn)
    XCTAssert(isCloseEnough(d.legacyDriverSecsAndNanos, sn))
  }
  func testReadAndWriteBuildRecord() throws {
    let version = "Apple Swift version 5.1 (swiftlang-1100.0.270.13 clang-1100.0.33.7)"
    let options = "abbbfbcaf36b93e58efaadd8271ff142"
    let file2 = "/Volumes/AS/repos/swift-driver/sandbox/sandbox/sandbox/file2.swift"
    let main = "/Volumes/AS/repos/swift-driver/sandbox/sandbox/sandbox/main.swift"
    let gazorp = "/Volumes/gazorp.swift"
    let inputString =
      """
      version: "\(version)"
      options: "\(options)"
      build_time: [1570318779, 32357931]
      inputs:
        "\(file2)": !dirty [1570318778, 0]
        "\(main)": [1570083660, 0]
        "\(gazorp)": !private [0, 0]

      """
    let buildRecord = try XCTUnwrap (BuildRecord(contents: inputString, failedToReadOutOfDateMap: {_ in}))
    XCTAssertEqual(buildRecord.swiftVersion, version)
    XCTAssertEqual(buildRecord.argsHash, options)
    XCTAssertEqual(buildRecord.inputInfos.count, 3)
    XCTAssert(isCloseEnough(buildRecord.buildTime.legacyDriverSecsAndNanos,
                            [1570318779, 32357931]))

    XCTAssertEqual(try! buildRecord.inputInfos[VirtualPath.intern(path: file2 )]!.status,
                   .needsCascadingBuild)
    XCTAssert(try! isCloseEnough(
                XCTUnwrap(buildRecord.inputInfos[VirtualPath.intern(path: file2 )])
                  .previousModTime.legacyDriverSecsAndNanos,
                [1570318778, 0]))
    XCTAssertEqual(try! XCTUnwrap(buildRecord.inputInfos[VirtualPath.intern(path: gazorp)]).status,
                   .needsNonCascadingBuild)
    XCTAssertEqual(try! XCTUnwrap(buildRecord.inputInfos[VirtualPath.intern(path: gazorp)])
                    .previousModTime.legacyDriverSecsAndNanos,
                   [0, 0])
    XCTAssertEqual(try! XCTUnwrap(buildRecord.inputInfos[VirtualPath.intern(path: main  )]).status,
                   .upToDate)
    XCTAssert(try! isCloseEnough(XCTUnwrap(buildRecord.inputInfos[VirtualPath.intern(path: main  )])
                                   .previousModTime.legacyDriverSecsAndNanos,
                                 [1570083660, 0]))

    let outputString = try XCTUnwrap (buildRecord.encode(currentArgsHash: options,
                                                         diagnosticEngine: DiagnosticsEngine()))
    XCTAssertEqual(inputString, outputString)
  }
  /// The date conversions are not exact
  func isCloseEnough(_ a: [Int], _ b: [Int]) -> Bool {
    a[0] == b[0] && abs(a[1] - b[1]) <= 100
  }


  /// Run a test with two files, main and other.swift, passing on the additional arguments
  /// expecting certain diagnostics.
  private func runDriver(
    with otherArgs: [String],
    expecting expectations: [Diagnostic.Message],
    alsoExpectingWhenAutolinking autolinkExpectations: [Diagnostic.Message] = []
  ) throws {
    try withTemporaryDirectory { path in
      let main = path.appending(component: "main.swift")
      try localFileSystem.writeFileContents(main) {
        $0 <<< "let foo = 1"
      }
      let other = path.appending(component: "other.swift")
      try localFileSystem.writeFileContents(other) {
        $0 <<< "let bar = 2"
      }
      try assertDriverDiagnostics(args: [
        "swiftc", "-module-name", "theModule", "-working-directory", path.pathString,
        main.pathString, other.pathString
      ] + otherArgs) {driver, verifier in
        verifier.forbidUnexpected(.error, .warning, .note, .remark, .ignored)

        expectations.forEach {verifier.expect($0)}
        if driver.isAutolinkExtractJobNeeded {
          autolinkExpectations.forEach {verifier.expect($0)}
        }

        let jobs = try driver.planBuild()
        try driver.run(jobs: jobs)
      }
    }
  }

  func testShowJobLifecycleAndIncremental() throws {
    // Legacy MacOS driver output:
    //    Adding standard job to task queue: {compile: main.o <= main.swift}
    //    Added to TaskQueue: {compile: main.o <= main.swift}
    //    Adding standard job to task queue: {compile: other.o <= other.swift}
    //    Added to TaskQueue: {compile: other.o <= other.swift}
    //    Job finished: {compile: main.o <= main.swift}
    //    Job finished: {compile: other.o <= other.swift}

    try runDriver( with: [
      "-c",
      "-driver-show-job-lifecycle",
      "-driver-show-incremental",
    ],
    expecting: [
      .remark("Starting Compiling main.swift"),
      .remark("Finished Compiling main.swift"),
      .remark("Starting Compiling other.swift"),
      .remark("Finished Compiling other.swift"),
    ],
    alsoExpectingWhenAutolinking: [
      .remark("Starting Extracting autolink information for module theModule"),
      .remark("Finished Extracting autolink information for module theModule"),
    ])

  }
  func testNoIncremental() throws {
    try runDriver( with: [
      "-c",
      "-incremental",
    ],
    expecting: [
      .warning("ignoring -incremental (currently requires an output file map)")
    ])
    // Legacy driver output:
    //    <unknown>:0: warning: ignoring -incremental (currently requires an output file map)
  }
}

// MARK: - IncrementalCompilation
final class IncrementalCompilationTests: XCTestCase {

  var tempDir: AbsolutePath = AbsolutePath("/tmp")

  var derivedDataDir: AbsolutePath {
    tempDir.appending(component: "derivedData")
  }

  let module = "theModule"
  var OFM: AbsolutePath {
    tempDir.appending(component: "OFM.json")
  }
  let baseNamesAndContents = [
    "main": "let foo = 1",
    "other": "let bar = foo"
  ]
  var inputPathsAndContents: [(AbsolutePath, String)] {
    baseNamesAndContents.map {
      (tempDir.appending(component: $0.key + ".swift"), $0.value)
    }
  }
  var derivedDataPath: AbsolutePath {
    tempDir.appending(component: "derivedData")
  }
  var masterSwiftDepsPath: AbsolutePath {
    derivedDataPath.appending(component: "\(module)-master.swiftdeps")
  }
  var autolinkIncrementalExpectations: [String] {
    [
      "Incremental compilation: Queuing Extracting autolink information for module \(module)",
    ]
  }
  var autolinkLifecycleExpectations: [String] {
    [
      "Starting Extracting autolink information for module \(module)",
      "Finished Extracting autolink information for module \(module)",
    ]
  }
  var commonArgs: [String] {
    [
      "swiftc",
      "-module-name", module,
      "-o", derivedDataPath.appending(component: module + ".o").pathString,
      "-output-file-map", OFM.pathString,
      "-driver-show-incremental",
      "-driver-show-job-lifecycle",
      "-enable-batch-mode",
      //        "-v",
      "-save-temps",
      "-incremental",
    ]
    + inputPathsAndContents.map {$0.0.pathString} .sorted()
  }

  override func setUp() {
    self.tempDir = try! withTemporaryDirectory(removeTreeOnDeinit: false) {$0}
    try! localFileSystem.createDirectory(derivedDataPath)
    OutputFileMapCreator.write(module: module,
                               inputPaths: inputPathsAndContents.map {$0.0},
                               derivedData: derivedDataPath,
                               to: OFM)
    for (base, contents) in baseNamesAndContents {
      let filePath = tempDir.appending(component: "\(base).swift")
      try! localFileSystem.writeFileContents(filePath) {
        $0 <<< contents
      }
    }
  }

  deinit {
    try? localFileSystem.removeFileTree(tempDir)
  }
}

extension IncrementalCompilationTests {
  func doABuild(_ message: String,
                checkDiagnostics: Bool,
                extraArguments: [String],
                expectingRemarks texts: [String],
                whenAutolinking: [String]) throws {
    try doABuild(
      message,
      checkDiagnostics: checkDiagnostics,
      extraArguments: extraArguments,
      expecting: texts.map {.remark($0)},
      expectingWhenAutolinking: whenAutolinking.map {.remark($0)})
  }

  func doABuild(_ message: String,
                checkDiagnostics: Bool,
                extraArguments: [String],
                expecting expectations: [Diagnostic.Message],
                expectingWhenAutolinking autolinkExpectations: [Diagnostic.Message]) throws {
    print("*** starting build \(message) ***", to: &stderrStream); stderrStream.flush()

    func doIt(_ driver: inout Driver) {
      let jobs = try! driver.planBuild()
      try? driver.run(jobs: jobs)
    }

    guard let sdkArgumentsForTesting = try Driver.sdkArgumentsForTesting()
    else {
      throw XCTSkip("Cannot perform this test on this host")
    }
    let allArgs = commonArgs + extraArguments + sdkArgumentsForTesting
    if checkDiagnostics {
      try assertDriverDiagnostics(args: allArgs) {driver, verifier in
        verifier.forbidUnexpected(.error, .warning, .note, .remark, .ignored)
        expectations.forEach {verifier.expect($0)}
        if driver.isAutolinkExtractJobNeeded {
          autolinkExpectations.forEach {verifier.expect($0)}
        }
        doIt(&driver)
      }
    }
    else {
      let diagnosticEngine = DiagnosticsEngine(handlers: [
        {print($0, to: &stderrStream); stderrStream.flush()}
      ])
      var driver = try Driver(args: allArgs, env: ProcessEnv.vars,
                              diagnosticsEngine: diagnosticEngine,
                              fileSystem: localFileSystem)
      doIt(&driver)
    }
    print("", to: &stderrStream); stderrStream.flush()
  }
}

extension IncrementalCompilationTests {

  func testOptionsParsing() throws {
    let optionPairs: [(
      Option, (IncrementalCompilationState.InitialStateComputer) -> Bool
    )] = [
      (.driverAlwaysRebuildDependents, {$0.alwaysRebuildDependents}),
      (.driverShowIncremental, {$0.reporter != nil}),
      (.driverEmitFineGrainedDependencyDotFileAfterEveryImport, {$0.emitDependencyDotFileAfterEveryImport}),
      (.driverVerifyFineGrainedDependencyGraphAfterEveryImport, {$0.verifyDependencyGraphAfterEveryImport}),
      (.enableIncrementalImports, {$0.isCrossModuleIncrementalBuildEnabled}),
      (.disableIncrementalImports, {!$0.isCrossModuleIncrementalBuildEnabled}),
    ]

    for (driverOption, stateOptionFn) in optionPairs {
      try doABuild(
        "initial",
        checkDiagnostics: false,
        extraArguments: [ driverOption.spelling ],
        expectingRemarks: [],
        whenAutolinking: [])

      guard let sdkArgumentsForTesting = try Driver.sdkArgumentsForTesting()
      else {
        throw XCTSkip("Cannot perform this test on this host")
      }
      var driver = try Driver(args: self.commonArgs + [
        driverOption.spelling,
      ] + sdkArgumentsForTesting)
      _ = try driver.planBuild()
      XCTAssertFalse(driver.diagnosticEngine.hasErrors)
      let state = try XCTUnwrap(driver.incrementalCompilationState)
      XCTAssertTrue(stateOptionFn(state.moduleDependencyGraph.info))
    }
  }
}

extension IncrementalCompilationTests {

  // FIXME: why does it fail on Linux in CI?
  func testIncrementalDiagnostics() throws {
    #if !os(Linux)
    try testIncremental(checkDiagnostics: true)
    #endif
  }

  // FIXME: Expect failure in Linux in CI just as testIncrementalDiagnostics
  func testAlwaysRebuildDependents() throws {
    #if !os(Linux)
    try tryInitial(checkDiagnostics: true)
    tryTouchingMainAlwaysRebuildDependents(checkDiagnostics: true)
    #endif
  }

  func testIncremental() throws {
    try testIncremental(checkDiagnostics: false)
  }

  func testDependencyDotFiles() throws {
    expectNoDotFiles()
    try tryInitial(extraArguments: ["-driver-emit-fine-grained-dependency-dot-file-after-every-import"])
    expect(dotFilesFor: [
      "main.swiftdeps",
      DependencyGraphDotFileWriter.moduleDependencyGraphBasename,
      "other.swiftdeps",
      DependencyGraphDotFileWriter.moduleDependencyGraphBasename,
    ])
  }

  func testDependencyDotFilesCross() throws {
    expectNoDotFiles()
    try tryInitial(extraArguments: [
      "-driver-emit-fine-grained-dependency-dot-file-after-every-import",
    ])
    removeDotFiles()
    tryTouchingOther(extraArguments: [
      "-driver-emit-fine-grained-dependency-dot-file-after-every-import",
    ])

    expect(dotFilesFor: [
      DependencyGraphDotFileWriter.moduleDependencyGraphBasename,
      "other.swiftdeps",
      DependencyGraphDotFileWriter.moduleDependencyGraphBasename,
    ])
  }

  func expectNoDotFiles() {
    guard localFileSystem.exists(derivedDataDir) else { return }
    try! localFileSystem.getDirectoryContents(derivedDataDir)
      .forEach {derivedFile in
        XCTAssertFalse(derivedFile.hasSuffix("dot"))
      }
  }

  func removeDotFiles() {
    try! localFileSystem.getDirectoryContents(derivedDataDir)
      .filter {$0.hasSuffix(".dot")}
      .map {derivedDataDir.appending(component: $0)}
      .forEach {try! localFileSystem.removeFileTree($0)}
  }

  func expect(dotFilesFor importedFiles: [String]) {
    let expectedDotFiles = Set(
      importedFiles.enumerated()
      .map { offset, element in "\(element).\(offset).dot" })
    let actualDotFiles = Set(
      try! localFileSystem.getDirectoryContents(derivedDataDir)
      .filter {$0.hasSuffix(".dot")})

    let missingDotFiles = expectedDotFiles.subtracting(actualDotFiles)
      .sortedByDotFileSequenceNumbers()
    let extraDotFiles = actualDotFiles.subtracting(expectedDotFiles)
      .sortedByDotFileSequenceNumbers()

    XCTAssertEqual(missingDotFiles, [])
    XCTAssertEqual(extraDotFiles, [])
  }

  /// Ensure that the mod date of the input comes back exactly the same via the build-record.
  /// Otherwise the up-to-date calculation in `IncrementalCompilationState` will fail.
  func testBuildRecordDateAccuracy() throws {
    try tryInitial()
    (1...10).forEach { n in
      tryNoChange(checkDiagnostics: true)
    }
  }

  func testIncremental(checkDiagnostics: Bool) throws {
    try tryInitial(checkDiagnostics: checkDiagnostics)
    #if true // sometimes want to skip for debugging
    tryNoChange(checkDiagnostics: checkDiagnostics)
    tryTouchingOther(checkDiagnostics: checkDiagnostics)
    tryTouchingBoth(checkDiagnostics: checkDiagnostics)
    #endif
    tryReplacingMain(checkDiagnostics: checkDiagnostics)
  }


  func tryInitial(checkDiagnostics: Bool = false,
                  extraArguments: [String] = []
  ) throws {
    try doABuild(
      "initial",
      checkDiagnostics: checkDiagnostics,
      extraArguments: extraArguments,
      expectingRemarks: [
        // Leave off the part after the colon because it varies on Linux:
        // MacOS: The operation could not be completed. (TSCBasic.FileSystemError error 3.).
        // Linux: The operation couldn’t be completed. (TSCBasic.FileSystemError error 3.)
        "Enabling incremental cross-module building",
        "Incremental compilation: Incremental compilation could not read build record at",
        "Incremental compilation: Disabling incremental build: could not read build record",
        "Incremental compilation: Created dependency graph from swiftdeps files",
        "Found 2 batchable jobs",
        "Forming into 1 batch",
        "Adding {compile: main.swift} to batch 0",
        "Adding {compile: other.swift} to batch 0",
        "Forming batch job from 2 constituents: main.swift, other.swift",
        "Starting Compiling main.swift, other.swift",
        "Finished Compiling main.swift, other.swift",
        "Starting Linking theModule",
        "Finished Linking theModule",
      ],
      whenAutolinking: autolinkLifecycleExpectations)
  }
  func tryNoChange(checkDiagnostics: Bool = false,
                   extraArguments: [String] = []
  ) {
    try! doABuild(
      "no-change",
      checkDiagnostics: checkDiagnostics,
      extraArguments: extraArguments,
      expectingRemarks: [
        "Enabling incremental cross-module building",
        "Incremental compilation: Read dependency graph",
        "Incremental compilation: May skip current input:  {compile: main.o <= main.swift}",
        "Incremental compilation: May skip current input:  {compile: other.o <= other.swift}",
        "Incremental compilation: Skipping input:  {compile: main.o <= main.swift}",
        "Incremental compilation: Skipping input:  {compile: other.o <= other.swift}",
        "Skipped Compiling main.swift",
        "Skipped Compiling other.swift",
      ],
      whenAutolinking: [])
  }
  func tryTouchingOther(checkDiagnostics: Bool = false,
                        extraArguments: [String] = []
  ) {
    touch("other")
    try! doABuild(
      "non-propagating",
      checkDiagnostics: checkDiagnostics,
      extraArguments: extraArguments,
      expectingRemarks: [
        "Enabling incremental cross-module building",
        "Incremental compilation: May skip current input:  {compile: main.o <= main.swift}",
        "Incremental compilation: Scheduing changed input  {compile: other.o <= other.swift}",
        "Incremental compilation: Queuing (initial):  {compile: other.o <= other.swift}",
        "Incremental compilation: not scheduling dependents of other.swift; unknown changes",
        "Incremental compilation: Skipping input:  {compile: main.o <= main.swift}",
        "Incremental compilation: Read dependency graph",
        "Found 1 batchable job",
        "Forming into 1 batch",
        "Adding {compile: other.swift} to batch 0",
        "Forming batch job from 1 constituents: other.swift",
        "Starting Compiling other.swift",
        "Finished Compiling other.swift",
        "Starting Linking theModule",
        "Finished Linking theModule",
        "Skipped Compiling main.swift",
    ],
    whenAutolinking: autolinkLifecycleExpectations)
  }
  func tryTouchingBoth(checkDiagnostics: Bool = false,
                       extraArguments: [String] = []
 ) {
    touch("main")
    touch("other")
    try! doABuild(
      "non-propagating, both touched",
      checkDiagnostics: checkDiagnostics,
      extraArguments: extraArguments,
      expectingRemarks: [
        "Enabling incremental cross-module building",
        "Incremental compilation: Read dependency graph",
        "Incremental compilation: Scheduing changed input  {compile: main.o <= main.swift}",
        "Incremental compilation: Scheduing changed input  {compile: other.o <= other.swift}",
        "Incremental compilation: Queuing (initial):  {compile: main.o <= main.swift}",
        "Incremental compilation: Queuing (initial):  {compile: other.o <= other.swift}",
        "Incremental compilation: not scheduling dependents of main.swift; unknown changes",
        "Incremental compilation: not scheduling dependents of other.swift; unknown changes",
        "Found 2 batchable jobs",
        "Forming into 1 batch",
        "Adding {compile: main.swift} to batch 0",
        "Adding {compile: other.swift} to batch 0",
        "Forming batch job from 2 constituents: main.swift, other.swift",
        "Starting Compiling main.swift, other.swift",
        "Finished Compiling main.swift, other.swift",
        "Starting Linking theModule",
        "Finished Linking theModule",
    ],
    whenAutolinking: autolinkLifecycleExpectations)
  }

  func tryReplacingMain(checkDiagnostics: Bool = false,
                        extraArguments: [String] = []
  ) {
    replace(contentsOf: "main", with: "let foo = \"hello\"")
    try! doABuild(
      "propagating into 2nd wave",
      checkDiagnostics: checkDiagnostics,
      extraArguments: extraArguments,
      expectingRemarks: [
        "Enabling incremental cross-module building",
        "Incremental compilation: Read dependency graph",
        "Incremental compilation: Scheduing changed input  {compile: main.o <= main.swift}",
        "Incremental compilation: May skip current input:  {compile: other.o <= other.swift}",
        "Incremental compilation: Queuing (initial):  {compile: main.o <= main.swift}",
        "Incremental compilation: not scheduling dependents of main.swift; unknown changes",
        "Incremental compilation: Skipping input:  {compile: other.o <= other.swift}",
        "Found 1 batchable job",
        "Forming into 1 batch",
        "Adding {compile: main.swift} to batch 0",
        "Forming batch job from 1 constituents: main.swift",
        "Starting Compiling main.swift",
        "Finished Compiling main.swift",
        "Incremental compilation: Fingerprint changed for interface of source file main.swiftdeps in main.swiftdeps",
        "Incremental compilation: Fingerprint changed for implementation of source file main.swiftdeps in main.swiftdeps",
        "Incremental compilation: Traced: interface of source file main.swiftdeps in main.swift -> interface of top-level name 'foo' in main.swift -> implementation of source file other.swiftdeps in other.swift",
        "Incremental compilation: Queuing because of dependencies discovered later:  {compile: other.o <= other.swift}",
        "Incremental compilation: Scheduling invalidated  {compile: other.o <= other.swift}",
        "Found 1 batchable job",
        "Forming into 1 batch",
        "Adding {compile: other.swift} to batch 0",
        "Forming batch job from 1 constituents: other.swift",
        "Starting Compiling other.swift",
        "Finished Compiling other.swift",
        "Starting Linking theModule",
        "Finished Linking theModule",
      ],
      whenAutolinking: autolinkLifecycleExpectations)
  }

  func tryTouchingMainAlwaysRebuildDependents(checkDiagnostics: Bool = false,
                                              extraArguments: [String] = []
  ) {
    touch("main")
    let extraArgument = "-driver-always-rebuild-dependents"
    try! doABuild(
      "non-propagating but \(extraArgument)",
      checkDiagnostics: checkDiagnostics,
      extraArguments: [extraArgument],
      expectingRemarks: [
        "Enabling incremental cross-module building",
        "Incremental compilation: Read dependency graph",
        "Incremental compilation: May skip current input:  {compile: other.o <= other.swift}",
        "Incremental compilation: Queuing (initial):  {compile: main.o <= main.swift}",
        "Incremental compilation: scheduling dependents of main.swift; -driver-always-rebuild-dependents",
        "Incremental compilation: Traced: interface of top-level name 'foo' in main.swift -> implementation of source file other.swiftdeps in other.swift",
        "Incremental compilation: Found dependent of main.swift:  {compile: other.o <= other.swift}",
        "Incremental compilation: Scheduing changed input  {compile: main.o <= main.swift}",
        "Incremental compilation: Immediately scheduling dependent on main.swift  {compile: other.o <= other.swift}",
        "Incremental compilation: Queuing because of the initial set:  {compile: other.o <= other.swift}",
        "Found 2 batchable jobs",
        "Forming into 1 batch",
        "Adding {compile: main.swift} to batch 0",
        "Adding {compile: other.swift} to batch 0",
        "Forming batch job from 2 constituents: main.swift, other.swift",
        "Starting Compiling main.swift, other.swift",
        "Finished Compiling main.swift, other.swift",
        "Starting Linking theModule",
        "Finished Linking theModule",
      ],
      whenAutolinking: autolinkLifecycleExpectations)
  }

  func touch(_ name: String) {
    print("*** touching \(name) ***", to: &stderrStream); stderrStream.flush()
    let (path, contents) = try! XCTUnwrap(inputPathsAndContents.filter {$0.0.pathString.contains(name)}.first)
    try! localFileSystem.writeFileContents(path) { $0 <<< contents }
  }

  private func replace(contentsOf name: String, with replacement: String ) {
    print("*** replacing \(name) ***", to: &stderrStream); stderrStream.flush()
    let path = try! XCTUnwrap(inputPathsAndContents.filter {$0.0.pathString.contains("/" + name + ".swift")}.first).0
    let previousContents = try! localFileSystem.readFileContents(path).cString
    try! localFileSystem.writeFileContents(path) { $0 <<< replacement }
    let newContents = try! localFileSystem.readFileContents(path).cString
    XCTAssert(previousContents != newContents, "\(path.pathString) unchanged after write")
    XCTAssert(replacement == newContents, "\(path.pathString) failed to write")
  }

  /// Ensure that autolink output file goes with .o directory, to not prevent incremental omission of
  /// autolink job.
  /// Much of the code below is taking from testLinking(), but uses the output file map code here.
  func testAutolinkOutputPath() {
    var env = ProcessEnv.vars
    env["SWIFT_DRIVER_TESTS_ENABLE_EXEC_PATH_FALLBACK"] = "1"
    env["SWIFT_DRIVER_SWIFT_AUTOLINK_EXTRACT_EXEC"] = "/garbage/swift-autolink-extract"
    env["SWIFT_DRIVER_DSYMUTIL_EXEC"] = "/garbage/dsymutil"

    var driver = try! Driver(
      args: commonArgs
        + ["-emit-library", "-target", "x86_64-unknown-linux"],
      env: env)
    let plannedJobs = try! driver.planBuild()
    let autolinkExtractJob = try! XCTUnwrap(
      plannedJobs
        .filter { $0.kind == .autolinkExtract }
        .first)
    let autoOuts = autolinkExtractJob.outputs.filter {$0.type == .autolink}
    XCTAssertEqual(autoOuts.count, 1)
    let autoOut = autoOuts[0]
    let expected = AbsolutePath(derivedDataPath, "\(module).autolink")
    XCTAssertEqual(autoOut.file.absolutePath, expected)
  }
}

class CrossModuleIncrementalBuildTests: XCTestCase {
  func makeOutputFileMap(
    in workingDirectory: AbsolutePath,
    for files: [AbsolutePath]
  ) -> String {
    """
    {
      "": {
        "swift-dependencies": "\(workingDirectory.appending(component: "module.swiftdeps"))"
      }
    """.appending(files.map { file in
      """
      ,
      "\(file)": {
        "dependencies": "\(file.basenameWithoutExt + ".d")",
        "object": "\(file.pathString + ".o")",
        "swiftmodule": "\(file.basenameWithoutExt + "~partial.swiftmodule")",
        "swift-dependencies": "\(file.basenameWithoutExt + ".swiftdeps")"
        }
      """
    }.joined(separator: "\n").appending("\n}"))
  }
  
  func testEmbeddedModuleDependencies() throws {
    try withTemporaryDirectory { path in
      try localFileSystem.changeCurrentWorkingDirectory(to: path)
      do {
        let magic = path.appending(component: "magic.swift")
        try localFileSystem.writeFileContents(magic) {
          $0 <<< "public func castASpell() {}"
        }

        let ofm = path.appending(component: "ofm.json")
        try localFileSystem.writeFileContents(ofm) {
          $0 <<< self.makeOutputFileMap(in: path, for: [ magic ])
        }

        var driver = try Driver(args: [
          "swiftc",
          "-incremental",
          "-emit-module",
          "-output-file-map", ofm.pathString,
          "-module-name", "MagicKit",
          "-working-directory", path.pathString,
          "-c",
          magic.pathString,
        ])
        let jobs = try driver.planBuild()
        try driver.run(jobs: jobs)
      }

      let main = path.appending(component: "main.swift")
      try localFileSystem.writeFileContents(main) {
        $0 <<< "import MagicKit\n"
        $0 <<< "castASpell()"
      }

      let ofm = path.appending(component: "ofm2.json")
      try localFileSystem.writeFileContents(ofm) {
        $0 <<< self.makeOutputFileMap(in: path, for: [ main ])
      }

      var driver = try Driver(args: [
        "swiftc",
        "-incremental",
        "-emit-module",
        "-output-file-map", ofm.pathString,
        "-module-name", "theModule",
        "-I", path.pathString,
        "-working-directory", path.pathString,
        "-c",
        main.pathString,
      ])

      let jobs = try driver.planBuild()
      try driver.run(jobs: jobs)

      let sourcePath = path.appending(component: "main.swiftdeps")
      let data = try localFileSystem.readFileContents(sourcePath)
      let graph = try XCTUnwrap(SourceFileDependencyGraph(data: data,
                                                          from: DependencySource(VirtualPath.absolute(sourcePath).intern())!,
                                                          fromSwiftModule: false))
      XCTAssertEqual(graph.majorVersion, 1)
      XCTAssertEqual(graph.minorVersion, 0)
      graph.verify()

      var foundNode = false
      let swiftmodulePath = ExternalDependency(fileName: path.appending(component: "MagicKit.swiftmodule").pathString)
      graph.forEachNode { node in
        if case .externalDepend(swiftmodulePath) = node.key.designator {
          XCTAssertFalse(foundNode)
          foundNode = true
          XCTAssertEqual(node.key.aspect, .interface)
          XCTAssertTrue(node.defsIDependUpon.isEmpty)
          XCTAssertFalse(node.isProvides)
        }
      }
      XCTAssertTrue(foundNode)
    }
  }
}

