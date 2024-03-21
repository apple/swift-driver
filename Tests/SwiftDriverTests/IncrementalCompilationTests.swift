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
import Foundation

@_spi(Testing) import SwiftDriver
import SwiftOptions
import TestUtilities

// MARK: - Instance variables and initialization
final class IncrementalCompilationTests: XCTestCase {

  var tempDir: AbsolutePath = try! AbsolutePath(validating: "/tmp")
  var explicitModuleCacheDir: AbsolutePath = try! AbsolutePath(validating: "/tmp/ModuleCache")

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
  func inputPath(basename: String) -> AbsolutePath {
    tempDir.appending(component: basename + ".swift")
  }
  var inputPathsAndContents: [(AbsolutePath, String)] {
    baseNamesAndContents.map {
      (inputPath(basename: $0.key), $0.value)
    }
  }
  var derivedDataPath: AbsolutePath {
    tempDir.appending(component: "derivedData")
  }
  var masterSwiftDepsPath: AbsolutePath {
    derivedDataPath.appending(component: "\(module)-master.swiftdeps")
  }
  var priorsPath: AbsolutePath {
    derivedDataPath.appending(component: "\(module)-master.priors")
  }
  func swiftDepsPath(basename: String) -> AbsolutePath {
    derivedDataPath.appending(component: "\(basename).swiftdeps")
  }
  fileprivate var autolinkIncrementalExpectedDiags: [Diagnostic.Message] {
    queuingExtractingAutolink(module)
  }
  fileprivate var autolinkLifecycleExpectedDiags: [Diagnostic.Message] {
    extractingAutolink(module)
  }
  var commonArgs: [String] {
    [
      "swiftc",
      "-module-name", module,
      "-o", derivedDataPath.appending(component: module + ".o").nativePathString(escaped: true),
      "-output-file-map", OFM.nativePathString(escaped: true),
      "-driver-show-incremental",
      "-driver-show-job-lifecycle",
      "-enable-batch-mode",
      //        "-v",
      "-save-temps",
      "-incremental",
      "-no-color-diagnostics",
    ]
    + inputPathsAndContents.map {$0.0.nativePathString(escaped: true)} .sorted()
  }
  var explicitBuildArgs: [String] {
    ["-explicit-module-build",
     "-module-cache-path", explicitModuleCacheDir.nativePathString(escaped: true),
     // Disable implicit imports to keep tests simpler
     "-Xfrontend", "-disable-implicit-concurrency-module-import",
     "-Xfrontend", "-disable-implicit-string-processing-module-import",
     "-I", explicitCDependenciesPath.nativePathString(escaped: true),
     "-I", explicitSwiftDependenciesPath.nativePathString(escaped: true)] + extraExplicitBuildArgs
  }
  var extraExplicitBuildArgs: [String] = []

  override func setUp() {
    self.tempDir = try! withTemporaryDirectory(removeTreeOnDeinit: false) {$0}
    self.explicitModuleCacheDir = tempDir.appending(component: "ModuleCache")
    try! localFileSystem.createDirectory(derivedDataPath)
    OutputFileMapCreator.write(module: module,
                               inputPaths: inputPathsAndContents.map {$0.0},
                               derivedData: derivedDataPath,
                               to: OFM)
    for (base, contents) in baseNamesAndContents {
      write(contents, to: base)
    }
    let driver = try! Driver(args: ["swiftc", "-v"])
    if driver.isFrontendArgSupported(.moduleLoadMode) {
      self.extraExplicitBuildArgs = ["-Xfrontend", "-module-load-mode", "-Xfrontend", "prefer-interface"]
    }
  }

  deinit {
    try? localFileSystem.removeFileTree(tempDir)
  }
}

// MARK: - Misc. tests
extension IncrementalCompilationTests {

  func testOptionsParsing() throws {
    let optionPairs: [(
      Option, (IncrementalCompilationState.IncrementalDependencyAndInputSetup) -> Bool
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
        whenAutolinking: []
      ) {}

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
      XCTAssertTrue(stateOptionFn(state.info))
    }
  }

  /// Ensure that autolink output file goes with .o directory, to not prevent incremental omission of
  /// autolink job.
  /// Much of the code below is taking from testLinking(), but uses the output file map code here.
  func testAutolinkOutputPath() throws {
    var env = ProcessEnv.vars
    env["SWIFT_DRIVER_TESTS_ENABLE_EXEC_PATH_FALLBACK"] = "1"
    env["SWIFT_DRIVER_SWIFT_AUTOLINK_EXTRACT_EXEC"] = "/garbage/swift-autolink-extract"
    env["SWIFT_DRIVER_DSYMUTIL_EXEC"] = "/garbage/dsymutil"

    var driver = try Driver(
      args: commonArgs
        + ["-emit-library", "-target", "x86_64-unknown-linux"],
      env: env)
    let plannedJobs = try driver.planBuild()
    let autolinkExtractJob = try XCTUnwrap(
      plannedJobs
        .filter { $0.kind == .autolinkExtract }
        .first)
    let autoOuts = autolinkExtractJob.outputs.filter {$0.type == .autolink}
    XCTAssertEqual(autoOuts.count, 1)
    let autoOut = autoOuts[0]
    let expected = try AbsolutePath(validating: "\(module).autolink", relativeTo: derivedDataPath)
    XCTAssertEqual(autoOut.file.absolutePath, expected)
  }
}

// MARK: - Dot file tests
extension IncrementalCompilationTests {
  func testDependencyDotFiles() throws {
    expectNoDotFiles()
    try buildInitialState(extraArguments: ["-driver-emit-fine-grained-dependency-dot-file-after-every-import"])
    expect(dotFilesFor: [
      "main.swift",
      DependencyGraphDotFileWriter.moduleDependencyGraphBasename,
      "other.swift",
      DependencyGraphDotFileWriter.moduleDependencyGraphBasename,
    ])
  }

  func testDependencyDotFilesCross() throws {
    expectNoDotFiles()
    try buildInitialState(extraArguments: [
      "-driver-emit-fine-grained-dependency-dot-file-after-every-import",
    ])
    removeDotFiles()
    try checkNoPropagation(extraArguments: [
      "-driver-emit-fine-grained-dependency-dot-file-after-every-import",
    ])

    expect(dotFilesFor: [
      DependencyGraphDotFileWriter.moduleDependencyGraphBasename,
      "other.swift",
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

  private func expect(dotFilesFor importedFiles: [String]) {
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
}

// MARK: - Post-compile jobs
extension IncrementalCompilationTests {
  /// Ensure that if an output of post-compile job is missing, the job gets rerun.
  func testIncrementalPostCompileJob() throws {
    #if !os(Linux)
    let driver = try XCTUnwrap(buildInitialState(checkDiagnostics: true))
    for postCompileOutput in try driver.postCompileOutputs() {
      let absPostCompileOutput = try XCTUnwrap(postCompileOutput.file.absolutePath)
      try localFileSystem.removeFileTree(absPostCompileOutput)
      XCTAssertFalse(localFileSystem.exists(absPostCompileOutput))
      try checkNullBuild()
      XCTAssertTrue(localFileSystem.exists(absPostCompileOutput))
    }
    #endif
  }
}
fileprivate extension Driver {
  func postCompileOutputs() throws -> [TypedVirtualPath] {
    try XCTUnwrap(incrementalCompilationState).jobsAfterCompiles.flatMap {$0.outputs}
  }
}

// MARK: - Explicit Module Build incremental tests
extension IncrementalCompilationTests {
  private var testExplicitDependencyInputsPath: AbsolutePath {
    var root: AbsolutePath = try! AbsolutePath(validating: #file)
    while root.basename != "Tests" {
      root = root.parentDirectory
    }
    return root.parentDirectory.appending(component: "TestInputs")
  }

  private var explicitCDependenciesPath: AbsolutePath {
    testExplicitDependencyInputsPath.appending(component: "ExplicitModuleBuilds")
      .appending(component: "CHeaders")
  }
  private var explicitSwiftDependenciesPath: AbsolutePath {
    testExplicitDependencyInputsPath.appending(component: "ExplicitModuleBuilds")
      .appending(component: "Swift")
  }

  func testExplicitIncrementalSimpleBuild() throws {
    try buildInitialState(explicitModuleBuild: true)
    try checkNullBuild(explicitModuleBuild: true)
  }

  // Simple re-use of a prior inter-module dependency graph on a null build
  func testExplicitIncrementalSimpleBuildCheckDiagnostics() throws {
    try buildInitialState(checkDiagnostics: true, explicitModuleBuild: true)
    try checkNullBuild(checkDiagnostics: true, explicitModuleBuild: true)
  }

  // Source files have changed but the inter-module dependency graph still up-to-date
  func testExplicitIncrementalBuildCheckGraphReuseOnChange() throws {
    try buildInitialState(checkDiagnostics: true, explicitModuleBuild: true)
    try checkReactionToTouchingAll(checkDiagnostics: true, explicitModuleBuild: true)
  }

  // Adding an import invalidates prior inter-module dependency graph.
  func testExplicitIncrementalBuildNewImport() throws {
    try buildInitialState(checkDiagnostics: true, explicitModuleBuild: true)
    // Introduce a new import. This will cause a re-scan and a re-build of 'other.swift'
    replace(contentsOf: "other", with: "import E;let bar = foo")
    try doABuild(
      "add import to 'other'",
      checkDiagnostics: true,
      extraArguments: explicitBuildArgs,
      whenAutolinking: autolinkLifecycleExpectedDiags
    ) {
      readGraph
      enablingCrossModule
      readInterModuleGraph
      // Ensure a re-scan was performed
      explicitMustReScanDueToChangedImports
      maySkip("main")
      schedulingChangedInitialQueuing("other")
      skipping("main")
      findingBatchingCompiling("other")
      reading(deps: "other")
      fingerprintsChanged("other")
      fingerprintsMissingOfTopLevelName(name: "bar", "other")
      moduleOutputNotFound("E")
      moduleWillBeRebuiltOutOfDate("E")
      explicitModulesWillBeRebuilt(["E"])
      compilingExplicitSwiftDependency("E")
      skipped("main")
      schedLinking
    }
  }

  // A dependency has changed one of its inputs
  func testExplicitIncrementalBuildChangedDependency() throws {
    // Add an import of 'E' to make sure followup changes has consistent inputs
    replace(contentsOf: "other", with: "import E;let bar = foo")
    try buildInitialState(checkDiagnostics: false, explicitModuleBuild: true)

    // Just update the time-stamp of one of the module dependencies and use a value
    // it is defined in.
    touch(try AbsolutePath(validating: explicitSwiftDependenciesPath.appending(component: "E.swiftinterface").pathString))
    replace(contentsOf: "other", with: "import E;let bar = foo + moduleEValue")

    // Changing a dependency will mean that we both re-run the dependency scan,
    // and also ensure that all source-files are re-built with a non-cascading build
    // since the source files themselves have not changed.
    try doABuild(
      "update dependency (E) interface timestamp",
      checkDiagnostics: true,
      extraArguments: explicitBuildArgs,
      whenAutolinking: autolinkLifecycleExpectedDiags
    ) {
      readGraph
      enablingCrossModule
      readInterModuleGraph
      // Ensure the above 'touch' is detected and causes a re-scan
      explicitDependencyModuleOlderThanInput("E")
      explicitMustReScanDueToChangedDependencyInput
      noFingerprintInSwiftModule("E.swiftinterface")
      dependencyNewerThanNode("E.swiftinterface")
      dependencyNewerThanNode("E.swiftinterface") // FIXME: Why do we see this twice?
      maySkip("main")
      schedulingChanged("other")
      invalidatedExternally("main", "other")
      queuingInitial("main", "other")
      notSchedulingDependentsUnknownChanges("other")
      findingBatchingCompiling("main", "other")
      explicitDependencyModuleOlderThanInput("E")
      moduleWillBeRebuiltOutOfDate("E")
      explicitModulesWillBeRebuilt(["E"])
      compilingExplicitSwiftDependency("E")
    }
  }

  // A dependency has changed one of its inputs, ensure
  // other modules that depend on it are invalidated also.
  //
  //             test
  //             /   \
  //             Y   T
  //            / \ / \
  //           H   R   J
  //            \       \
  //             \-------G
  //
  // On this graph, inputs of 'G' are updated, causing it to be re-built
  // as well as all modules on paths from root to it: 'Y', 'H', 'T','J'
  func testExplicitIncrementalBuildChangedDependencyInvalidatesUpstreamDependencies() throws {
    // Add an import of 'B', 'C' to make sure followup changes has consistent inputs
    replace(contentsOf: "other", with: "import Y;import T")
    try buildInitialState(checkDiagnostics: false, explicitModuleBuild: true)

    // Just update the time-stamp of one of the module dependencies
    touch(try AbsolutePath(validating: explicitSwiftDependenciesPath.appending(component: "G.swiftinterface").pathString))

    // Changing a dependency will mean that we both re-run the dependency scan,
    // and also ensure that all source-files are re-built with a non-cascading build
    // since the source files themselves have not changed.
    try doABuild(
      "update dependency (G) interface timestamp",
      checkDiagnostics: true,
      extraArguments: explicitBuildArgs,
      whenAutolinking: autolinkLifecycleExpectedDiags
    ) {
      readGraph
      enablingCrossModule
      readInterModuleGraph
      // Ensure the above 'touch' is detected and causes a re-scan
      explicitDependencyModuleOlderThanInput("G")
      explicitMustReScanDueToChangedDependencyInput
      noFingerprintInSwiftModule("G.swiftinterface")
      dependencyNewerThanNode("G.swiftinterface")
      dependencyNewerThanNode("G.swiftinterface") // FIXME: Why do we see this twice?
      reading(deps: "main")
      reading(deps: "other")
      fingerprintsMissingOfTopLevelName(name: "foo", "main")
      maySkip("main")
      maySkip("other")
      invalidatedExternally("main", "other")
      queuingInitial("main", "other")
      findingBatchingCompiling("main", "other")
      explicitDependencyModuleOlderThanInput("G")
      explicitDependencyInvalidatedDownstream("J")
      explicitDependencyInvalidatedDownstream("T")
      explicitDependencyInvalidatedDownstream("Y")
      explicitDependencyInvalidatedDownstream("H")
      explicitModulesWillBeRebuilt(["G", "H", "J", "T", "Y"])
      moduleWillBeRebuiltOutOfDate("G")
      compilingExplicitSwiftDependency("G")
      compilingExplicitSwiftDependency("J")
      compilingExplicitSwiftDependency("T")
      compilingExplicitSwiftDependency("Y")
      compilingExplicitSwiftDependency("H")
      schedulingPostCompileJobs
      linking
    }
  }
}

extension IncrementalCompilationTests {
  // A dependency has changed one of its inputs
  func testIncrementalImplicitBuildChangedDependency() throws {
    let extraAruments = ["-I", explicitCDependenciesPath.nativePathString(escaped: true),
                         "-I", explicitSwiftDependenciesPath.nativePathString(escaped: true)]
    replace(contentsOf: "other", with: "import E;let bar = foo")
    try buildInitialState(checkDiagnostics: false, extraArguments: extraAruments)
    touch(try AbsolutePath(validating: explicitSwiftDependenciesPath.appending(component: "E.swiftinterface").pathString))
    replace(contentsOf: "other", with: "import E;let bar = foo + moduleEValue")

    // Changing a dependency will mean that we both re-run the dependency scan,
    // and also ensure that all source-files are re-built with a non-cascading build
    // since the source files themselves have not changed.
    try doABuild(
      "update dependency (E) interface timestamp",
      checkDiagnostics: false,
      extraArguments: extraAruments,
      whenAutolinking: autolinkLifecycleExpectedDiags
    ) {
      readGraph
      enablingCrossModule
      schedulingNoncascading("main", "other")
      missing("main")
      missing("other")
      queuingInitial("main", "other")
      notSchedulingDependentsDoNotNeedCascading("main", "other")
      findingBatchingCompiling("main", "other")
    }
  }
}

// MARK: - Simpler incremental tests
extension IncrementalCompilationTests {

  // FIXME: why does it fail on Linux in CI?
  func testIncrementalDiagnostics() throws {
    #if !os(Linux)
    try testIncremental(checkDiagnostics: true)
    #endif
  }

  func testIncremental() throws {
    try testIncremental(checkDiagnostics: false)
  }

  func testIncremental(checkDiagnostics: Bool) throws {
    try buildInitialState(checkDiagnostics: checkDiagnostics)
#if true // sometimes want to skip for debugging
    try checkNullBuild(checkDiagnostics: checkDiagnostics)
    try checkNoPropagation(checkDiagnostics: checkDiagnostics)
    try checkReactionToTouchingAll(checkDiagnostics: checkDiagnostics)
#endif
    try checkPropagationOfTopLevelChange(checkDiagnostics: checkDiagnostics)
  }

  func testFileMapMissingMainEntry() throws {
    try buildInitialState(checkDiagnostics: true)
    OutputFileMapCreator.write(
      module: module, inputPaths: inputPathsAndContents.map {$0.0},
      derivedData: derivedDataPath, to: OFM, excludeMainEntry: true)
    try doABuild("output file map missing main entry", checkDiagnostics: true, extraArguments: [], whenAutolinking: []) {
      missingMainDependencyEntry
      disablingIncremental
      foundBatchableJobs(2)
      formingOneBatch
      addingToBatchThenForming("main", "other")
      compiling("main", "other")
      startingLinking
      finishedLinking
    }
  }

  func testFileMapMissingMainEntryWMO() throws {
    try buildInitialState(checkDiagnostics: true)
    guard let sdkArgumentsForTesting = try Driver.sdkArgumentsForTesting()
    else {
      throw XCTSkip("Cannot perform this test on this host")
    }

    OutputFileMapCreator.write(
      module: module, inputPaths: inputPathsAndContents.map {$0.0},
      derivedData: derivedDataPath, to: OFM, excludeMainEntry: true)

    let args = [
      "swiftc",
      "-module-name", module,
      "-o", derivedDataPath.appending(component: module + ".o").pathString,
      "-output-file-map", OFM.pathString,
      "-incremental",
      "-whole-module-optimization",
      "-no-color-diagnostics",
    ] + inputPathsAndContents.map {$0.0.pathString}.sorted() + sdkArgumentsForTesting
    _ = try doABuild(whenAutolinking: [], expecting: disabledForWMO, arguments: args)
  }

  // FIXME: Expect failure in Linux in CI just as testIncrementalDiagnostics
  func testAlwaysRebuildDependents() throws {
#if !os(Linux)
    try buildInitialState(checkDiagnostics: true)
    try checkAlwaysRebuildDependents(checkDiagnostics: true)
#endif
  }

  /// Ensure that the mod date of the input comes back exactly the same via the build-record.
  /// Otherwise the up-to-date calculation in `IncrementalCompilationState` will fail.
  func testBuildRecordDateAccuracy() throws {
    try buildInitialState()
    try (1...10).forEach { n in
      try checkNullBuild(checkDiagnostics: true)
    }
  }

  func testNullBuildNoEmitModule() throws {
    let extraArguments = ["-experimental-emit-module-separately", "-emit-module"]
    try buildInitialState(extraArguments: extraArguments)
    let driver = try checkNullBuild(extraArguments: extraArguments)
    let mandatoryJobs = try XCTUnwrap(driver.incrementalCompilationState?.mandatoryJobsInOrder)
    XCTAssertTrue(mandatoryJobs.isEmpty)
  }

    func testNullBuildNoVerify() throws {
      let extraArguments = ["-experimental-emit-module-separately", "-emit-module", "-emit-module-interface", "-enable-library-evolution", "-verify-emitted-module-interface"]
      try buildInitialState(extraArguments: extraArguments)
      let driver = try checkNullBuild(extraArguments: extraArguments)
      let mandatoryJobs = try XCTUnwrap(driver.incrementalCompilationState?.mandatoryJobsInOrder)
      XCTAssertTrue(mandatoryJobs.isEmpty)
    }

  func testSymlinkModification() throws {
    // Remap
    // main.swift -> links/main.swift
    // other.swift -> links/other.swift
    for (file, _) in self.inputPathsAndContents {
      try localFileSystem.createDirectory(tempDir.appending(component: "links"))
      let linkTarget = tempDir.appending(component: "links").appending(component: file.basename)
      try localFileSystem.move(from: file, to: linkTarget)
      try localFileSystem.removeFileTree(file)
      try localFileSystem.createSymbolicLink(file, pointingAt: linkTarget, relative: false)
    }
    try buildInitialState()
    try checkReactionToTouchingSymlinks(checkDiagnostics: true)
    try checkReactionToTouchingSymlinkTargets(checkDiagnostics: true)
  }

  /// Ensure that the driver can detect and then recover from a priors version mismatch
  func testPriorsVersionDetectionAndRecovery() throws {
#if _runtime(_ObjC)
    // create a baseline priors
    try buildInitialState(checkDiagnostics: true)
    let driver = try checkNullBuild(checkDiagnostics: true)

    // Read the priors, change the minor version, and write it back out
    let outputFileMap = try XCTUnwrap(driver.incrementalCompilationState).info.outputFileMap
    let info = IncrementalCompilationState.IncrementalDependencyAndInputSetup
      .mock(outputFileMap: outputFileMap)
    let priorsModTime = try info.blockingConcurrentAccessOrMutation {
      () -> Date in
      let priorsWithOldVersion = try XCTUnwrap(ModuleDependencyGraph.read(
        from: .absolute(priorsPath),
        info: info))
      let priorsModTime = try localFileSystem.getFileInfo(priorsPath).modTime
      let incrementedVersion = ModuleDependencyGraph.serializedGraphVersion.withAlteredMinor
      try priorsWithOldVersion.write(to: .absolute(priorsPath),
                                     on: localFileSystem,
                                     buildRecord: priorsWithOldVersion.buildRecord,
                                     mockSerializedGraphVersion: incrementedVersion)
      return priorsModTime
    }
    try setModTime(of: .absolute(priorsPath), to: priorsModTime)

    try checkReactionToObsoletePriors()
    try checkNullBuild(checkDiagnostics: true)
#endif
  }
}

// MARK: - Test adding an input
extension IncrementalCompilationTests {

  func testAddingInput() throws {
#if !os(Linux)
  try testAddingInput(newInput: "another", defining: "nameInAnother")
#endif
  }

  /// Test the addition of an input file
  ///
  /// - Parameters:
  ///   - newInput: basename without extension of new input file
  ///   - topLevelName: a new top level name defined in the new input
  private func testAddingInput(newInput: String, defining topLevelName: String
  ) throws {
    try buildInitialState(checkDiagnostics: true).withModuleDependencyGraph { initial in
      initial.ensureOmits(sourceBasenameWithoutExt: newInput)
      initial.ensureOmits(name: topLevelName)
    }

    write("let \(topLevelName) = foo", to: newInput)
    let newInputsPath = inputPath(basename: newInput)
    OutputFileMapCreator.write(module: module,
                               inputPaths: inputPathsAndContents.map {$0.0} + [newInputsPath],
                               derivedData: derivedDataPath,
                               to: OFM)
    try checkReactionToAddingInput(newInput: newInput, definingTopLevel: topLevelName)
    try checkRestorationOfIncrementalityAfterAddition(newInput: newInput, definingTopLevel: topLevelName)
  }
}

// MARK: - Incremental file removal tests
/// In order to ensure robustness, test what happens under various conditions when a source file is
/// removed.
/// The following is a lot of work to get something that prints nicely. Need an enum with both a string and an int value.
fileprivate enum RemovalTestOption: String, CaseIterable, Comparable, Hashable, CustomStringConvertible {
  case
  removeInputFromInvocation,
  removeSwiftDepsOfRemovedInput,
  removedFileDependsOnChangedFile

  private static let byInt  = [Int: Self](uniqueKeysWithValues: allCases.enumerated().map{($0, $1)})
  private static let intFor = [Self: Int](uniqueKeysWithValues: allCases.enumerated().map{($1, $0)})

  var intValue: Int {Self.intFor[self]!}
  init(fromInt i: Int) {self = Self.byInt[i]!}

  static func < (lhs: RemovalTestOption, rhs: RemovalTestOption) -> Bool {
    lhs.intValue < rhs.intValue
  }
  var mask: Int { 1 << intValue}
  static let maxIntValue = allCases.map {$0.intValue} .max()!
  static let maxCombinedValue = (1 << (maxIntValue + 1)) - 1

  var description: String { rawValue }
}

/// Only 5 elements, an array is fine
fileprivate typealias RemovalTestOptions = [RemovalTestOption]

extension RemovalTestOptions {
  fileprivate static let allCombinations: [RemovalTestOptions] =
  (0...RemovalTestOption.maxCombinedValue) .map(decoding)

  fileprivate static func decoding(_ bits: Int) -> Self {
    RemovalTestOption.allCases.filter { opt in
      (1 << opt.intValue) & bits != 0
    }
  }
}

extension IncrementalCompilationTests {
  func testRemoval() throws {
#if _runtime(_ObjC)
    for optionsToTest in RemovalTestOptions.allCombinations {
      try testRemoval(optionsToTest)
    }
#endif
  }

  private func testRemoval(_ options: RemovalTestOptions) throws {
    setUp() // clear derived data, restore output file map
    print("\n*** testRemoval \(options) ***", to: &stderrStream); stderrStream.flush()

    let newInput = "another"
    let topLevelName = "nameInAnother"
    try testAddingInput(newInput: newInput, defining: topLevelName)

    let removeInputFromInvocation = options.contains(.removeInputFromInvocation)
    let removeSwiftDepsOfRemovedInput = options.contains(.removeSwiftDepsOfRemovedInput)
    let removedFileDependsOnChangedFileAndMainWasChanged = options.contains(.removedFileDependsOnChangedFile)

    _ = try self.checkNonincrementalAfterRemoving(
      removedInput: newInput,
      defining: topLevelName,
      removeInputFromInvocation: removeInputFromInvocation,
      removeSwiftDepsOfRemovedInput: removeSwiftDepsOfRemovedInput)

    if removedFileDependsOnChangedFileAndMainWasChanged {
      replace(contentsOf: "main", with: "let foo = \"hello\"")
    }

    try checkRestorationOfIncrementalityAfterRemoval(
      removedInput: newInput,
      defining: topLevelName,
      removeInputFromInvocation: removeInputFromInvocation,
      removeSwiftDepsOfRemovedInput: removeSwiftDepsOfRemovedInput,
      removedFileDependsOnChangedFileAndMainWasChanged: removedFileDependsOnChangedFileAndMainWasChanged)
  }
}

// MARK: - Incremental argument hashing tests
extension IncrementalCompilationTests {
  func testNullBuildWhenAddingAndRemovingArgumentsNotAffectingIncrementalBuilds() throws {
    // Adding, removing, or changing the arguments of options which don't affect incremental builds should result in a null build.
    try buildInitialState(extraArguments: ["-driver-batch-size-limit", "5", "-debug-diagnostic-names"])
    let driver = try checkNullBuild(extraArguments: ["-driver-batch-size-limit", "10", "-diagnostic-style", "swift"])
    let mandatoryJobs = try XCTUnwrap(driver.incrementalCompilationState?.mandatoryJobsInOrder)
    XCTAssertTrue(mandatoryJobs.isEmpty)
  }

  func testChangingOptionArgumentLeadsToRecompile() throws {
    // If an option affects incremental builds, changing only the argument should trigger a full recompile.
    try buildInitialState(extraArguments: ["-user-module-version", "1.0"])
    try doABuild(
      "change user module version",
      checkDiagnostics: true,
      extraArguments: ["-user-module-version", "1.1"],
      whenAutolinking: autolinkLifecycleExpectedDiags
    ) {
      enablingCrossModule
      readGraph
      differentArgsPassed
      disablingIncrementalDifferentArgsPassed
      findingBatchingCompiling("main", "other")
      reading(deps: "main", "other")
      schedLinking
    }
  }

  func testOptionReorderingLeadsToRecompile() throws {
    // Reordering options which affect incremental builds should trigger a full recompile.
    try buildInitialState(extraArguments: ["-warnings-as-errors", "-no-warnings-as-errors"])
    try doABuild(
      "change user module version",
      checkDiagnostics: true,
      extraArguments: ["-no-warnings-as-errors", "-warnings-as-errors"],
      whenAutolinking: autolinkLifecycleExpectedDiags
    ) {
      enablingCrossModule
      readGraph
      differentArgsPassed
      disablingIncrementalDifferentArgsPassed
      findingBatchingCompiling("main", "other")
      reading(deps: "main", "other")
      schedLinking
    }
  }

  func testArgumentReorderingLeadsToRecompile() throws {
    // Reordering the arguments of an option which affect incremental builds should trigger a full recompile.
    try buildInitialState(extraArguments: ["-Ifoo", "-Ibar"])
    try doABuild(
      "change user module version",
      checkDiagnostics: true,
      extraArguments: ["-Ibar", "-Ifoo"],
      whenAutolinking: autolinkLifecycleExpectedDiags
    ) {
      enablingCrossModule
      readGraph
      differentArgsPassed
      disablingIncrementalDifferentArgsPassed
      findingBatchingCompiling("main", "other")
      reading(deps: "main", "other")
      schedLinking
    }
  }
}

// MARK: - Incremental test stages
extension IncrementalCompilationTests {
  /// Setup the initial post-build state.
  ///
  /// - Parameters:
  ///   - checkDiagnostics: If true verify the diagnostics
  ///   - extraArguments: Additional command-line arguments
  /// - Returns: The `Driver` object
  @discardableResult
  private func buildInitialState(
    checkDiagnostics: Bool = false,
    extraArguments: [String] = [],
    explicitModuleBuild: Bool = false
  ) throws -> Driver {
    @DiagsBuilder var implicitBuildInitialRemarks: [Diagnostic.Message] {
      // Leave off the part after the colon because it varies on Linux:
      // MacOS: The operation could not be completed. (TSCBasic.FileSystemError error 3.).
      // Linux: The operation couldn’t be completed. (TSCBasic.FileSystemError error 3.)
      enablingCrossModule
      findingBatchingCompiling("main", "other")
      reading(deps: "main", "other")
      schedLinking
    }
    @DiagsBuilder var explicitBuildInitialRemarks: [Diagnostic.Message] {
      implicitBuildInitialRemarks
      explicitDidNotReadInterModuleGraph
      compilingExplicitClangDependency("SwiftShims")
      compilingExplicitSwiftDependency("Swift")
      compilingExplicitSwiftDependency("SwiftOnoneSupport")
    }

    return try doABuild("initial",
                        checkDiagnostics: checkDiagnostics,
                        extraArguments: explicitModuleBuild ? explicitBuildArgs + extraArguments : extraArguments,
                        whenAutolinking: autolinkLifecycleExpectedDiags
    ) { explicitModuleBuild ? explicitBuildInitialRemarks : implicitBuildInitialRemarks }
  }

  /// Try a build with no changes.
  ///
  /// - Parameters:
  ///   - checkDiagnostics: If true verify the diagnostics
  ///   - extraArguments: Additional command-line arguments
  @discardableResult
  private func checkNullBuild(
    checkDiagnostics: Bool = false,
    extraArguments: [String] = [],
    explicitModuleBuild: Bool = false
  ) throws -> Driver {
    @DiagsBuilder var implicitBuildNullRemarks: [Diagnostic.Message] {
      enablingCrossModule
      readGraph
      maySkip("main", "other")
      skipping("main", "other")
      skipped("main", "other")
      skippingLinking
    }
    @DiagsBuilder var explicitBuildNullRemarks: [Diagnostic.Message] {
      implicitBuildNullRemarks
      readInterModuleGraph
      interModuleDependencyGraphUpToDate
    }

    return try doABuild(
      "as is",
      checkDiagnostics: checkDiagnostics,
      extraArguments: explicitModuleBuild ? explicitBuildArgs + extraArguments : extraArguments,
      whenAutolinking: []
    ) { explicitModuleBuild ? explicitBuildNullRemarks : implicitBuildNullRemarks }
  }

  /// Check reaction to touching a non-propagating input.
  ///
  /// - Parameters:
  ///   - checkDiagnostics: If true verify the diagnostics
  ///   - extraArguments: Additional command-line arguments
  private func checkNoPropagation(
    checkDiagnostics: Bool = false,
    extraArguments: [String] = []
  ) throws {
    touch("other")
    try doABuild(
      "touch other; non-propagating",
      checkDiagnostics: checkDiagnostics,
      extraArguments: extraArguments,
      whenAutolinking: autolinkLifecycleExpectedDiags
    ) {
      enablingCrossModule
      maySkip("main")
      schedulingChangedInitialQueuing("other")
      skipping("main")
      readGraph
      findingBatchingCompiling("other")
      reading(deps: "other")
      // Since the code is `bar = foo`, there is no fingprint for `bar`
      fingerprintsMissingOfTopLevelName(name: "bar", "other")
      schedLinking
      skipped("main")
    }
  }

  /// Check reaction to touching both inputs.
  ///
  /// - Parameters:
  ///   - checkDiagnostics: If true verify the diagnostics
  ///   - extraArguments: Additional command-line arguments
  private func checkReactionToTouchingAll(
    checkDiagnostics: Bool = false,
    extraArguments: [String] = [],
    explicitModuleBuild: Bool = false
  ) throws {
    @DiagsBuilder var implicitBuildRemarks: [Diagnostic.Message] {
      readGraph
      enablingCrossModule
      schedulingChangedInitialQueuing("main", "other")
      findingBatchingCompiling("main", "other")
      reading(deps: "main", "other")
      // Because `let foo = 1`, there is no fingerprint
      fingerprintsMissingOfTopLevelName(name: "foo", "main")
      fingerprintsMissingOfTopLevelName(name: "bar", "other")
      schedLinking
    }
    @DiagsBuilder var explicitBuildRemarks: [Diagnostic.Message] {
      implicitBuildRemarks
      readInterModuleGraph
      interModuleDependencyGraphUpToDate
    }

    touch("main")
    touch("other")
    try doABuild(
      "touch both; non-propagating",
      checkDiagnostics: checkDiagnostics,
      extraArguments: explicitModuleBuild ? explicitBuildArgs + extraArguments : extraArguments,
      whenAutolinking: autolinkLifecycleExpectedDiags
    ) { explicitModuleBuild ? explicitBuildRemarks : implicitBuildRemarks }
  }

  /// Check reaction to changing a top-level declaration.
  ///
  /// - Parameters:
  ///   - checkDiagnostics: If true verify the diagnostics
  ///   - extraArguments: Additional command-line arguments
  private func checkPropagationOfTopLevelChange(
    checkDiagnostics: Bool = false,
    extraArguments: [String] = []
  ) throws {
    replace(contentsOf: "main", with: "let foo = \"hello\"")
    try doABuild(
      "replace contents of main; propagating into 2nd wave",
      checkDiagnostics: checkDiagnostics,
      extraArguments: extraArguments,
      whenAutolinking: autolinkLifecycleExpectedDiags
    ) {
      readGraph
      enablingCrossModule
      schedulingChanged("main")
      maySkip("other")
      queuingInitial("main")
      notSchedulingDependentsUnknownChanges("main")
      skipping("other")
      findingBatchingCompiling("main")
      reading(deps: "main")
      fingerprintsChanged("main")
      fingerprintsMissingOfTopLevelName(name: "foo", "main")
      trace {
        TraceStep(.interface, sourceFileProvide: "main")
        TraceStep(.interface, topLevel: "foo", input: "main")
        TraceStep(.implementation, sourceFileProvide: "other")
      }
      queuingLaterSchedInvalBatchLink("other")
      findingBatchingCompiling("other")
      reading(deps: "other")
      fingerprintsMissingOfTopLevelName(name: "bar", "other")
      schedLinking
    }
  }

  /// Check functioning of `-driver-always-rebuild-dependents`
  ///
  /// - Parameters:
  ///   - checkDiagnostics: If true verify the diagnostics
  ///   - extraArguments: Additional command-line arguments
  private func checkAlwaysRebuildDependents(
    checkDiagnostics: Bool = false,
    extraArguments: [String] = []
  ) throws {
    touch("main")
    let extraArgument = "-driver-always-rebuild-dependents"
    try doABuild(
      "touch main; non-propagating but \(extraArgument)",
      checkDiagnostics: checkDiagnostics,
      extraArguments: [extraArgument],
      whenAutolinking: autolinkLifecycleExpectedDiags
    ) {
      enablingCrossModule
      readGraph
      maySkip("other")
      queuingInitial("main")
      schedulingAlwaysRebuild("main")
      trace {
        TraceStep(.interface, topLevel: "foo", input: "main")
        TraceStep(.implementation, sourceFileProvide: "other")
      }
      foundDependent(of: "main", compiling: "other")
      schedulingChanged("main")
      schedulingDependent(of: "main", compiling: "other")
      queuingBecauseInitial("other")
      findingAndFormingBatch(2)
      addingToBatchThenForming("main", "other")
      schedulingPostCompileJobs
      compiling("main", "other")
      reading(deps: "main", "other")
      fingerprintsMissingOfTopLevelName(name: "foo", "main")
      fingerprintsMissingOfTopLevelName(name: "bar", "other")
      linking
    }
  }

  /// Check reaction to adding an input file.
  ///
  /// - Parameters:
  ///   - newInput: The basename without extension of the new file
  ///   - topLevelName: The top-level decl name added by the new file
  private func checkReactionToAddingInput(
    newInput: String,
    definingTopLevel topLevelName: String
  ) throws {
    let newInputsPath = inputPath(basename: newInput)
    let driver = try doABuild(
      "after addition of \(newInput)",
      checkDiagnostics: true,
      extraArguments: [newInputsPath.pathString],
      whenAutolinking: autolinkLifecycleExpectedDiags
    ) {
      readGraph
      enablingCrossModule
      maySkip("main", "other")
      schedulingNew(newInput)
      missing(newInput)
      queuingInitial(newInput)
      notSchedulingDependentsNoEntry(newInput)
      skipping("main", "other")
      findingBatchingCompiling(newInput)
      reading(deps: newInput)
      newDefinitionOfSourceFile(.interface,      newInput)
      newDefinitionOfSourceFile(.implementation, newInput)
      newDefinitionOfTopLevelName(.interface,      name: topLevelName, input: newInput)
      newDefinitionOfTopLevelName(.implementation, name: topLevelName, input: newInput)
      schedLinking
      skipped("main", "other")
    }

    try driver.withModuleDependencyGraph { graph in
      XCTAssert(graph.contains(sourceBasenameWithoutExt: newInput))
      XCTAssert(graph.contains(name: topLevelName))
    }
  }

  /// Ensure that incremental builds happen after an addition.
  ///
  /// - Parameters:
  ///   - newInput: The basename without extension of the new file
  ///   - topLevelName: The top-level decl name added by the new file
  private func checkRestorationOfIncrementalityAfterAddition(
    newInput: String,
    definingTopLevel topLevelName: String
  ) throws {
    let newInputPath = inputPath(basename: newInput)
    let driver = try doABuild(
      "after restoration of \(newInput)",
      checkDiagnostics: true,
      extraArguments: [newInputPath.pathString],
      whenAutolinking: autolinkLifecycleExpectedDiags
    ) {
      readGraph
      enablingCrossModule
      maySkip("main", "other", newInput)
      skipping("main", "other", newInput)
      skippingLinking
      skipped(newInput, "main", "other")
    }

    try driver.withModuleDependencyGraph { graph in
      XCTAssert(graph.contains(sourceBasenameWithoutExt: newInput))
      XCTAssert(graph.contains(name: topLevelName))
    }
  }

  /// Check fallback to nonincremental build after a removal.
  ///
  /// - Parameters:
  ///   - newInput: The basename without extension of the removed input
  ///   - defining: A top level name defined by the removed file
  ///   - includeInputInInvocation: include the removed input in the invocation
  private func checkNonincrementalAfterRemoving(
    removedInput: String,
    defining topLevelName: String,
    removeInputFromInvocation: Bool,
    removeSwiftDepsOfRemovedInput: Bool
  ) throws -> Driver {
    let extraArguments = removeInputFromInvocation
    ? [] : [inputPath(basename: removedInput).pathString]

    if removeSwiftDepsOfRemovedInput {
      removeSwiftDeps(removedInput)
    }

    let driver = try doABuild(
      "after removal of \(removedInput)",
      checkDiagnostics: true,
      extraArguments: extraArguments,
      whenAutolinking: autolinkLifecycleExpectedDiags
    ) {
      switch (removeInputFromInvocation, removeSwiftDepsOfRemovedInput) {
      case (false, false):
        // No change:
        readGraphAndSkipAll("main", "other", removedInput)
      case (true, _):
        // Give up on incremental if an input is removed:
        readGraph
        disabledForRemoval(removedInput)
        enablingCrossModule
        reading(deps: "main", "other")
        findingBatchingCompiling("main", "other")
        schedulingPostCompileJobs
        linking
      case (false, true):
        // Missing swiftdeps; compile it, read swiftdeps, link
        readGraph
        enablingCrossModule
        maySkip("main", "other", removedInput)
        missing(removedInput)
        queuingInitial(removedInput)
        skipping("main", "other")
        findingBatchingCompiling(removedInput)
        reading(deps: removedInput)
        fingerprintsMissingOfTopLevelName(name: topLevelName, removedInput)
        schedulingPostCompileJobs
        linking
        skipped("main", "other")
      }
    }

    if !removeInputFromInvocation {
      try driver.withModuleDependencyGraph { graph in
        graph.verifyGraph()
        XCTAssert(graph.contains(sourceBasenameWithoutExt: removedInput))
        XCTAssert(graph.contains(name: topLevelName))
      }
    }
    return driver
  }
}

// MARK: - Incremental test stages; checkRestorationOfIncrementalityAfterRemoval
extension IncrementalCompilationTests {
  /// Ensure that incremental builds happen after a removal.
  ///
  /// - Parameters:
  ///   - newInput: The basename without extension of the new file
  ///   - topLevelName: The top-level decl name added by the new file
  fileprivate func checkRestorationOfIncrementalityAfterRemoval(
    removedInput: String,
    defining topLevelName: String,
    removeInputFromInvocation: Bool,
    removeSwiftDepsOfRemovedInput: Bool,
    removedFileDependsOnChangedFileAndMainWasChanged: Bool
  ) throws {
    let inputs = ["main", "other"] + (removeInputFromInvocation ? [] : [removedInput])
    let extraArguments = removeInputFromInvocation
      ? [] : [inputPath(basename: removedInput).pathString]
    let mainChanged = removedFileDependsOnChangedFileAndMainWasChanged
    let changedInputs = mainChanged ? ["main"] : []
    let unchangedInputs = inputs.filter {!changedInputs.contains($0)}
    let affectedInputs = removeInputFromInvocation
      ? ["other"] : [removedInput, "other"]
    let affectedInputsInBuild = affectedInputs.filter(inputs.contains)
    let affectedInputsInInvocationOrder = inputs.filter(affectedInputsInBuild.contains)

    let driver = try doABuild(
      "restoring incrementality after removal of \(removedInput)",
      checkDiagnostics: true,
      extraArguments: extraArguments,
      whenAutolinking: autolinkLifecycleExpectedDiags
    ) {
      readGraph
      enablingCrossModule

      if changedInputs.isEmpty {
        skippingAll(inputs)
      } else {
        let swiftDepsReadAfterFirstWave = changedInputs
        let omittedFromFirstWave = unchangedInputs
        respondToChangedInputs(
          changedInputs: changedInputs,
          unchangedInputs: unchangedInputs,
          swiftDepsReadAfterFirstWave: swiftDepsReadAfterFirstWave,
          omittedFromFirstWave: omittedFromFirstWave)
        integrateChangedMainWithPriors(
          removedInput: removedInput,
          defining: topLevelName,
          affectedInputs: affectedInputs,
          affectedInputsInBuild: affectedInputsInBuild,
          affectedInputsInInvocationOrder: affectedInputsInInvocationOrder,
          removeInputFromInvocation: removeInputFromInvocation)
        schedLinking
      }
    }

    try driver.withModuleDependencyGraph { graph in
      graph.verifyGraph()
      if removeInputFromInvocation {
        graph.ensureOmits(sourceBasenameWithoutExt: removedInput)
        graph.ensureOmits(name: topLevelName)
      }
      else {
        XCTAssert(graph.contains(sourceBasenameWithoutExt: removedInput))
        XCTAssert(graph.contains(name: topLevelName))
      }
    }
  }

  @DiagsBuilder private func respondToChangedInputs(
    changedInputs: [String],
    unchangedInputs: [String],
    swiftDepsReadAfterFirstWave: [String],
    omittedFromFirstWave: [String]
  ) -> [Diagnostic.Message] {
    schedulingChanged(changedInputs)
    maySkip(unchangedInputs)
    queuingInitial(swiftDepsReadAfterFirstWave)
    notSchedulingDependentsUnknownChanges(changedInputs)
    skipping(omittedFromFirstWave)
    findingBatchingCompiling(swiftDepsReadAfterFirstWave)
    reading(deps: swiftDepsReadAfterFirstWave)
  }

  @DiagsBuilder private var addDefsWithoutGraph: [Diagnostic.Message] {
    for (input, name) in [("main", "foo"), ("other", "bar")] {
      newDefinitionOfSourceFile(.interface,      input)
      newDefinitionOfSourceFile(.implementation, input)
      newDefinitionOfTopLevelName(.interface,      name: name, input: input)
      newDefinitionOfTopLevelName(.implementation, name: name, input: input)
    }
  }

  @DiagsBuilder private func integrateChangedMainWithPriors(
    removedInput: String,
    defining topLevelName: String,
    affectedInputs: [String],
    affectedInputsInBuild: [String],
    affectedInputsInInvocationOrder: [String],
    removeInputFromInvocation: Bool
  ) -> [Diagnostic.Message]
  {
    fingerprintsChanged("main")
    fingerprintsMissingOfTopLevelName(name: "foo", "main")

    for input in affectedInputs {
      trace {
        TraceStep(.interface, sourceFileProvide: "main")
        TraceStep(.interface, topLevel: "foo", input: "main")
        TraceStep(.implementation, sourceFileProvide: input)
      }
    }
    queuingLater(affectedInputsInBuild)
    schedulingInvalidated(affectedInputsInBuild)
    findingBatchingCompiling(affectedInputsInInvocationOrder)
    reading(deps: "other")
    fingerprintsMissingOfTopLevelName(name: "bar", "other")

    let readingAnotherDeps = !removeInputFromInvocation // if removed, won't read it
    if readingAnotherDeps {
      reading(deps: removedInput)
      fingerprintsMissingOfTopLevelName(name: topLevelName, removedInput)
    }
  }

  private func checkReactionToObsoletePriors() throws {
    try doABuild(
      "check reaction to obsolete priors",
      checkDiagnostics: true,
      extraArguments: [],
      whenAutolinking: autolinkLifecycleExpectedDiags) {
        couldNotReadPriors
        enablingCrossModule
        findingBatchingCompiling("main", "other")
        reading(deps: "main")
        reading(deps: "other")
        schedLinking
    }
  }

  private func checkReactionToTouchingSymlinks(
    checkDiagnostics: Bool = false,
    extraArguments: [String] = []
  ) throws {
    Thread.sleep(forTimeInterval: 1)

    for (file, _) in self.inputPathsAndContents {
      try localFileSystem.removeFileTree(file)
      let linkTarget = tempDir.appending(component: "links").appending(component: file.basename)
      try localFileSystem.createSymbolicLink(file, pointingAt: linkTarget, relative: false)
    }

    try doABuild(
      "touch both symlinks; non-propagating",
      checkDiagnostics: checkDiagnostics,
      extraArguments: extraArguments,
      whenAutolinking: autolinkLifecycleExpectedDiags
    ) {
      enablingCrossModule
      readGraph
      maySkip("main", "other")
      skipping("main", "other")
      skippingLinking
      skipped("main", "other")
    }
  }

  private func checkReactionToTouchingSymlinkTargets(
    checkDiagnostics: Bool = false,
    extraArguments: [String] = []
  ) throws {
    Thread.sleep(forTimeInterval: 1)

    for (file, contents) in self.inputPathsAndContents {
      let linkTarget = tempDir.appending(component: "links").appending(component: file.basename)
      try! localFileSystem.writeFileContents(linkTarget) { $0.send(contents) }
    }

    try doABuild(
      "touch both symlink targets; non-propagating",
      checkDiagnostics: checkDiagnostics,
      extraArguments: extraArguments,
      whenAutolinking: autolinkLifecycleExpectedDiags
    ) {
      enablingCrossModule
      readGraph
      schedulingChangedInitialQueuing("main", "other")
      findingBatchingCompiling("main", "other")
      reading(deps: "main", "other")
      fingerprintsMissingOfTopLevelName(name: "foo", "main")
      fingerprintsMissingOfTopLevelName(name: "bar", "other")
      schedulingPostCompileJobs
      linking
    }
  }
}

// MARK: - Incremental test perturbation helpers
extension IncrementalCompilationTests {
  private func touch(_ name: String) {
    print("*** touching \(name) ***", to: &stderrStream); stderrStream.flush()
    let (path, _) = try! XCTUnwrap(inputPathsAndContents.filter {$0.0.pathString.contains(name)}.first)
    touch(path)
  }

  private func touch(_ path: AbsolutePath) {
    Thread.sleep(forTimeInterval: 1)
    let existingContents = try! localFileSystem.readFileContents(path)
    try! localFileSystem.writeFileContents(path) { $0.send(existingContents) }
  }

  /// Set modification time of a file
  ///
  /// - Parameters:
  ///   - path: The file whose modificaiton time to change
  ///   - newModTime: The desired modification time
  fileprivate func setModTime(of path: VirtualPath, to newModTime: Date) throws {
    var fileAttributes = try FileManager.default.attributesOfItem(atPath: path.name)
    fileAttributes[.modificationDate] = newModTime
    try FileManager.default.setAttributes(fileAttributes, ofItemAtPath: path.name)
  }

  private func removeInput(_ name: String) {
    print("*** removing input \(name) ***", to: &stderrStream); stderrStream.flush()
    try! localFileSystem.removeFileTree(inputPath(basename: name))
  }

  private func removeSwiftDeps(_ name: String) {
    print("*** removing swiftdeps \(name) ***", to: &stderrStream); stderrStream.flush()
    let swiftDepsPath = swiftDepsPath(basename: name)
    XCTAssert(localFileSystem.exists(swiftDepsPath))
    try! localFileSystem.removeFileTree(swiftDepsPath)
  }

  private func replace(contentsOf name: String, with replacement: String) {
    print("*** replacing \(name) ***", to: &stderrStream); stderrStream.flush()
    let path = inputPath(basename: name)
    let previousContents = try! localFileSystem.readFileContents(path).cString
    try! localFileSystem.writeFileContents(path) { $0.send(replacement) }
    let newContents = try! localFileSystem.readFileContents(path).cString
    XCTAssert(previousContents != newContents, "\(path.pathString) unchanged after write")
    XCTAssert(replacement == newContents, "\(path.pathString) failed to write")
  }

  private func write(_ contents: String, to basename: String) {
    print("*** writing \(contents) to \(basename)")
    try! localFileSystem.writeFileContents(inputPath(basename: basename)) { $0.send(contents) }
  }

  private func readPriors() -> ByteString? {
    try? localFileSystem.readFileContents(priorsPath)
  }

  private func writePriors( _ contents: ByteString) {
    try! localFileSystem.writeFileContents(priorsPath, bytes: contents)
  }
}

// MARK: - Graph inspection
extension Driver {
  /// Expose the protected ``ModuleDependencyGraph`` to a function and also prevent concurrent access or modification
  func withModuleDependencyGraph(_ fn: (ModuleDependencyGraph) throws -> Void) throws {
    let incrementalCompilationState = try XCTUnwrap(self.incrementalCompilationState, "no graph")
    try incrementalCompilationState.blockingConcurrentAccessOrMutationToProtectedState {
      try $0.testWithModuleDependencyGraph(fn)
    }
  }
  func verifyNoGraph() {
    XCTAssertNil(incrementalCompilationState)
  }
}

fileprivate extension ModuleDependencyGraph {
  /// A convenience for testing
  var allNodes: [Node] {
    var nodes = [Node]()
    nodeFinder.forEachNode {nodes.append($0)}
    return nodes
  }
  func contains(sourceBasenameWithoutExt target: String) -> Bool {
    allNodes.contains {$0.contains(sourceBasenameWithoutExt: target, in: self)}
  }
  func contains(name target: String) -> Bool {
    allNodes.contains {$0.contains(name: target, in: self)}
  }
  func ensureOmits(sourceBasenameWithoutExt target: String) {
    // Written this way to show the faulty node when the assertion fails
    nodeFinder.forEachNode { node in
      XCTAssertFalse(node.contains(sourceBasenameWithoutExt: target, in: self),
                     "graph should omit source: \(target)")
    }
  }
  func ensureOmits(name: String) {
    // Written this way to show the faulty node when the assertion fails
    nodeFinder.forEachNode { node in
      XCTAssertFalse(node.contains(name: name, in: self),
                     "graph should omit decl named: \(name)")
    }
  }
}

fileprivate extension ModuleDependencyGraph.Node {
  func contains(sourceBasenameWithoutExt target: String, in g: ModuleDependencyGraph) -> Bool {
    switch key.designator {
    case .sourceFileProvide(name: let name):
      return (try? VirtualPath(path: name.lookup(in: g)))
        .map {$0.basenameWithoutExt == target}
      ?? false
    case .externalDepend(let externalDependency):
      return externalDependency.path.map {
        $0.basenameWithoutExt == target
      }
      ?? false
    case .topLevel, .dynamicLookup, .nominal, .member, .potentialMember:
      return false
    }
  }

  func contains(name target: String, in g: ModuleDependencyGraph) -> Bool {
    switch key.designator {
    case .topLevel(name: let name),
      .dynamicLookup(name: let name):
      return name.lookup(in: g) == target
    case .externalDepend, .sourceFileProvide:
      return false
    case .nominal(context: let context),
         .potentialMember(context: let context):
      return context.lookup(in: g).range(of: target) != nil
    case .member(context: let context, name: let name):
      return context.lookup(in: g).range(of: target) != nil ||
                name.lookup(in: g) == target
    }
  }
}

// MARK: - Build helpers
extension IncrementalCompilationTests {
  @discardableResult
  fileprivate func doABuild(
   _ message: String,
  checkDiagnostics: Bool,
  extraArguments: [String],
  whenAutolinking autolinkExpectedDiags: [Diagnostic.Message],
  @DiagsBuilder expecting expectedDiags: () -> [Diagnostic.Message]
  ) throws -> Driver {
    print("*** starting build \(message) ***", to: &stderrStream); stderrStream.flush()

    guard let sdkArgumentsForTesting = try Driver.sdkArgumentsForTesting()
    else {
      throw XCTSkip("Cannot perform this test on this host")
    }
    let allArgs = commonArgs + extraArguments + sdkArgumentsForTesting

    return try checkDiagnostics
    ? doABuild(whenAutolinking: autolinkExpectedDiags,
               expecting: expectedDiags(),
               arguments: allArgs)
    : doABuildWithoutExpectations(arguments: allArgs)
  }

  private func doABuild(
    whenAutolinking autolinkExpectedDiags: [Diagnostic.Message],
    expecting expectedDiags: [Diagnostic.Message],
    arguments: [String]
  ) throws -> Driver {
    try assertDriverDiagnostics(args: arguments) {
      driver, verifier in
      verifier.forbidUnexpected(.error, .warning, .note, .remark, .ignored)

      expectedDiags.forEach {verifier.expect($0)}
      if driver.isAutolinkExtractJobNeeded {
        autolinkExpectedDiags.forEach {verifier.expect($0)}
      }
      doTheCompile(&driver)
      return driver
    }
  }

  private func doABuildWithoutExpectations(arguments: [String]) throws -> Driver {
    // If not checking, print out the diagnostics
    let diagnosticEngine = DiagnosticsEngine(handlers: [
      {print($0, to: &stderrStream); stderrStream.flush()}
    ])
    var driver = try Driver(args: arguments, env: ProcessEnv.vars,
                            diagnosticsEngine: diagnosticEngine,
                            fileSystem: localFileSystem)
    doTheCompile(&driver)
    // Add a newline after any diagnostics for readability
    print("", to: &stderrStream); stderrStream.flush()
    return driver
  }

  private func doTheCompile(_ driver: inout Driver) {
    let jobs = try! driver.planBuild()
    try? driver.run(jobs: jobs)
  }
}

// MARK: - Concisely specifying sequences of diagnostics

/// Build an array of diagnostics from a closure containing various things
@resultBuilder fileprivate enum DiagsBuilder {}
/// Build a series of messages from series of messages
extension DiagsBuilder {
  static func buildBlock(_ components: [Diagnostic.Message]...) -> [Diagnostic.Message] {
    components.flatMap {$0}
  }
}

/// A statement can be String, Message, or \[Message\]
extension DiagsBuilder {
  static func buildExpression(_ expression: String) -> [Diagnostic.Message] {
    // Default a string to a remark
    [.remark(expression)]
  }
  static func buildExpression(_ expression: [Diagnostic.Message]) -> [Diagnostic.Message] {
    expression
  }
  static func buildExpression(_ expression: Diagnostic.Message) -> [Diagnostic.Message] {
    [expression]
  }
}

/// Handle control structures
extension DiagsBuilder {
  static func buildArray(_ components: [[Diagnostic.Message]]) -> [Diagnostic.Message] {
    components.flatMap{$0}
  }
  static func buildOptional(_ component: [Diagnostic.Message]?) -> [Diagnostic.Message] {
    component ?? []
  }
  static func buildEither(first component: [Diagnostic.Message]) -> [Diagnostic.Message] {
    component
  }
  static func buildEither(second component: [Diagnostic.Message]) -> [Diagnostic.Message] {
    component
  }
}

// MARK: - Shorthand diagnostics & sequences

/// Allow tests to specify diagnostics without extra punctuation
fileprivate protocol DiagVerifiable {}

extension IncrementalCompilationTests: DiagVerifiable {}

extension DiagVerifiable {

  // MARK: - explicit builds
  @DiagsBuilder var explicitDidNotReadInterModuleGraph: [Diagnostic.Message] {
    "Incremental compilation: Incremental compilation did not attempt to read inter-module dependency graph."
  }
  @DiagsBuilder var explicitMustReScanCouldNotReadGraph: [Diagnostic.Message] {
    "Incremental compilation: Incremental build must re-run dependency scan: Could not read inter-module dependency graph at"
  }
  @DiagsBuilder var readInterModuleGraph: [Diagnostic.Message] {
    "Incremental compilation: Read inter-module dependency graph"
  }
  @DiagsBuilder var interModuleDependencyGraphUpToDate: [Diagnostic.Message] {
    "Incremental compilation: Confirmed prior inter-module dependency graph is up-to-date at"
  }
  @DiagsBuilder var explicitMustReScanDueToChangedImports: [Diagnostic.Message] {
    "Incremental compilation: Incremental build must re-run dependency scan: Target import set has changed."
  }
  @DiagsBuilder var explicitMustReScanDueToChangedDependencyInput: [Diagnostic.Message] {
    "Incremental compilation: Incremental build must re-run dependency scan: Not all dependencies are up-to-date."
  }
  @DiagsBuilder func explicitDependencyModuleOlderThanInput(_ dependencyModuleName: String) -> [Diagnostic.Message] {
    "Dependency module \(dependencyModuleName) is older than input file"
  }
  @DiagsBuilder func startCompilingExplicitClangDependency(_ dependencyModuleName: String) -> [Diagnostic.Message] {
    "Starting Compiling Clang module \(dependencyModuleName)"
  }
  @DiagsBuilder func finishCompilingExplicitClangDependency(_ dependencyModuleName: String) -> [Diagnostic.Message] {
    "Finished Compiling Clang module \(dependencyModuleName)"
  }
  @DiagsBuilder func startCompilingExplicitSwiftDependency(_ dependencyModuleName: String) -> [Diagnostic.Message] {
    "Starting Compiling Swift module \(dependencyModuleName)"
  }
  @DiagsBuilder func finishCompilingExplicitSwiftDependency(_ dependencyModuleName: String) -> [Diagnostic.Message] {
    "Finished Compiling Swift module \(dependencyModuleName)"
  }
  @DiagsBuilder func compilingExplicitClangDependency(_ dependencyModuleName: String) -> [Diagnostic.Message] {
    startCompilingExplicitClangDependency(dependencyModuleName)
    finishCompilingExplicitClangDependency(dependencyModuleName)
  }
  @DiagsBuilder func compilingExplicitSwiftDependency(_ dependencyModuleName: String) -> [Diagnostic.Message] {
    startCompilingExplicitSwiftDependency(dependencyModuleName)
    finishCompilingExplicitSwiftDependency(dependencyModuleName)
  }
  @DiagsBuilder func moduleOutputNotFound(_ moduleName: String) -> [Diagnostic.Message] {
    "Incremental compilation: Module output not found: '\(moduleName)'"
  }
  @DiagsBuilder func moduleWillBeRebuiltOutOfDate(_ moduleName: String) -> [Diagnostic.Message] {
    "Incremental compilation: Dependency module '\(moduleName)' will be re-built: Out-of-date"
  }
  @DiagsBuilder func explicitModulesWillBeRebuilt(_ moduleNames: [String]) -> [Diagnostic.Message] {
    "Incremental compilation: Following explicit module dependencies will be re-built: [\(moduleNames.joined(separator: ", "))]"
  }
  @DiagsBuilder func explicitDependencyInvalidatedDownstream(_ moduleName: String) -> [Diagnostic.Message] {
    "Incremental compilation: Dependency module '\(moduleName)' will be re-built: Invalidated by downstream dependency"
  }

  // MARK: - misc
  @DiagsBuilder var enablingCrossModule: [Diagnostic.Message] {
    "Incremental compilation: Enabling incremental cross-module building"
  }
  @DiagsBuilder func disabledForRemoval(_ removedInput: String) -> [Diagnostic.Message] {
    "Incremental compilation: Incremental compilation has been disabled, because the following inputs were used in the previous compilation but not in this one: \(removedInput).swift"
  }
  @DiagsBuilder var disabledForWMO: [Diagnostic.Message] {
    "Incremental compilation has been disabled: it is not compatible with whole module optimization"
  }
  // MARK: - build record
  @DiagsBuilder var cannotReadBuildRecord: [Diagnostic.Message] {
    "Incremental compilation: Incremental compilation could not read build record at"
  }
  @DiagsBuilder var disablingIncrementalCannotReadBuildRecord: [Diagnostic.Message] {
    "Incremental compilation: Disabling incremental build: could not read build record"
  }
  @DiagsBuilder var differentArgsPassed: [Diagnostic.Message] {
      "Incremental compilation: Incremental compilation has been disabled, because different arguments were passed to the compiler"
  }
  @DiagsBuilder var disablingIncrementalDifferentArgsPassed: [Diagnostic.Message] {
      "Incremental compilation: Disabling incremental build: different arguments were passed to the compiler"
  }
  @DiagsBuilder var missingMainDependencyEntry: [Diagnostic.Message] {
    .warning("ignoring -incremental; output file map has no master dependencies entry (\"swift-dependencies\" under \"\")")
  }
  @DiagsBuilder var disablingIncremental: [Diagnostic.Message] {
    "Incremental compilation: Disabling incremental build: no build record path"
  }
  // MARK: - graph
  @DiagsBuilder var createdGraphFromSwiftdeps: [Diagnostic.Message] {
    "Incremental compilation: Created dependency graph from swiftdeps files"
  }
  @DiagsBuilder var readGraph: [Diagnostic.Message] {
    "Incremental compilation: Read dependency graph"
  }
  @DiagsBuilder var couldNotReadPriors: [Diagnostic.Message] {
      .remark("Will not do cross-module incremental builds, wrong version of priors; expected")
  }
  // MARK: - dependencies
  @DiagsBuilder func reading(deps inputs: [String]) -> [Diagnostic.Message] {
    for input in inputs {
      "Incremental compilation: Reading dependencies from \(input).swift"
    }
  }
  @DiagsBuilder func reading(deps inputs: String...) -> [Diagnostic.Message] {
    reading(deps: inputs)
  }

  @DiagsBuilder func fingerprintChanged(_ aspect: DependencyKey.DeclAspect, _ input: String) -> [Diagnostic.Message] {
    "Incremental compilation: Fingerprint changed for existing \(aspect) of source file from \(input).swiftdeps in \(input).swift"
  }
 @DiagsBuilder func fingerprintsChanged(_ input: String) -> [Diagnostic.Message] {
    for aspect: DependencyKey.DeclAspect in [.interface, .implementation] {
      fingerprintChanged(aspect, input)
    }
  }

   @DiagsBuilder func fingerprintsMissingOfTopLevelName(name: String, _ input: String) -> [Diagnostic.Message] {
    for aspect: DependencyKey.DeclAspect in [.interface, .implementation] {
      "Incremental compilation: Fingerprint missing for existing \(aspect) of top-level name '\(name)' in \(input).swift"
    }
  }

  @DiagsBuilder func newDefinitionOfSourceFile(_ aspect: DependencyKey.DeclAspect, _ input: String) -> [Diagnostic.Message] {
    "Incremental compilation: New definition: \(aspect) of source file from \(input).swiftdeps in \(input).swift"
  }
  @DiagsBuilder func newDefinitionOfTopLevelName(_ aspect: DependencyKey.DeclAspect, name: String, input: String) -> [Diagnostic.Message] {
    "Incremental compilation: New definition: \(aspect) of top-level name '\(name)' in \(input).swift"
  }

  @DiagsBuilder func foundDependent(of defInput: String, compiling useInput: String) -> [Diagnostic.Message] {
    "Incremental compilation: Found dependent of \(defInput).swift:  {compile: \(useInput).o <= \(useInput).swift}"
  }
  @DiagsBuilder func hasMalformed(_ inputs: [String]) -> [Diagnostic.Message] {
    for newInput in inputs {
      "Incremental compilation: Has malformed dependency source; will queue  {compile: \(newInput).o <= \(newInput).swift}"
    }
  }
  @DiagsBuilder func hasMalformed(_ inputs: String...) -> [Diagnostic.Message] {
    hasMalformed(inputs)
  }
  @DiagsBuilder func invalidatedExternally(_ inputs: [String]) -> [Diagnostic.Message] {
    for input in inputs {
      "Incremental compilation: Invalidated externally; will queue  {compile: \(input).o <= \(input).swift}"
    }
  }
  @DiagsBuilder func invalidatedExternally(_ inputs: String...) -> [Diagnostic.Message] {
    invalidatedExternally(inputs)
  }
  @DiagsBuilder func failedToFindSource(_ input: String) -> [Diagnostic.Message] {
      .warning("Failed to find source file '\(input).swift' in command line, recovering with a full rebuild. Next build will be incremental.")
  }
  @DiagsBuilder func failedToReadSomeSource(compiling input: String) -> [Diagnostic.Message] {
    "Incremental compilation: Failed to read some dependencies source; compiling everything  {compile: \(input).o <= \(input).swift}"
  }

  @DiagsBuilder func noFingerprintInSwiftModule(_ dependencyFile: String) -> [Diagnostic.Message] {
    "No fingerprint in swiftmodule: Invalidating all nodes in newer: \(dependencyFile)"
  }
  @DiagsBuilder func dependencyNewerThanNode(_ dependencyFile: String) -> [Diagnostic.Message] {
    "Newer: \(dependencyFile) -> SwiftDriver.ModuleDependencyGraph.Node"
  }

  // MARK: - tracing
  @DiagsBuilder func trace(@TraceBuilder _ steps: () -> String) -> [Diagnostic.Message] {
    steps()
  }

  // MARK: - scheduling
  @DiagsBuilder func schedulingAlwaysRebuild(_ input: String) -> [Diagnostic.Message] {
    "Incremental compilation: scheduling dependents of \(input).swift; -driver-always-rebuild-dependents"
  }
  @DiagsBuilder func schedulingNew(_ input: String) -> [Diagnostic.Message] {
    "Incremental compilation: Scheduling new  {compile: \(input).o <= \(input).swift}"
  }

  @DiagsBuilder func schedulingChanged(_ inputs: [String]) -> [Diagnostic.Message] {
    for input in inputs {
      "Incremental compilation: Scheduling changed input  {compile: \(input).o <= \(input).swift}"
    }
  }
  @DiagsBuilder func schedulingChanged(_ inputs: String...) -> [Diagnostic.Message] {
    schedulingChanged(inputs)
  }

  @DiagsBuilder func schedulingNoncascading(_ inputs: [String]) -> [Diagnostic.Message] {
    for input in inputs {
      "Incremental compilation: Scheduling noncascading build  {compile: \(input).o <= \(input).swift}"
    }
  }
  @DiagsBuilder func schedulingNoncascading(_ inputs: String...) -> [Diagnostic.Message] {
    schedulingNoncascading(inputs)
  }

  @DiagsBuilder func schedulingInvalidated(_ inputs: [String]) -> [Diagnostic.Message] {
     for input in inputs {
       "Incremental compilation: Scheduling invalidated  {compile: \(input).o <= \(input).swift}"
     }
  }
  @DiagsBuilder func schedulingInvalidated(_ inputs: String...) -> [Diagnostic.Message] { schedulingInvalidated(inputs) }

  @DiagsBuilder func schedulingChangedInitialQueuing(_ inputs: String...) -> [Diagnostic.Message]  {
    for input in inputs {
      schedulingChanged(input)
      queuingInitial(input)
      notSchedulingDependentsUnknownChanges(input)
    }
  }

  @DiagsBuilder func schedulingDependent(of defInput: String, compiling useInput: String) -> [Diagnostic.Message] {
    "Incremental compilation: Immediately scheduling dependent on \(defInput).swift  {compile: \(useInput).o <= \(useInput).swift}"
  }

  @DiagsBuilder func notSchedulingDependentsNoEntry(_ input: String) -> [Diagnostic.Message] {
    "Incremental compilation: not scheduling dependents of \(input).swift: no entry in build record or dependency graph"
  }

  @DiagsBuilder func notSchedulingDependentsUnknownChanges(_ inputs: [String]) -> [Diagnostic.Message] {
    for input in inputs {
      "Incremental compilation: not scheduling dependents of \(input).swift; unknown changes"
    }
  }
  @DiagsBuilder func notSchedulingDependentsUnknownChanges(_ inputs: String...) -> [Diagnostic.Message] {
    notSchedulingDependentsUnknownChanges(inputs)
  }

  @DiagsBuilder func notSchedulingDependentsDoNotNeedCascading(_ inputs: [String]) -> [Diagnostic.Message] {
    for input in inputs {
      "Incremental compilation: not scheduling dependents of \(input).swift: does not need cascading build"
    }
  }
  @DiagsBuilder func notSchedulingDependentsDoNotNeedCascading(_ inputs: String...) -> [Diagnostic.Message] {
    notSchedulingDependentsDoNotNeedCascading(inputs)
  }

  @DiagsBuilder func missing(_ input: String) -> [Diagnostic.Message] {
    "Incremental compilation: Missing an output; will queue  {compile: \(input).o <= \(input).swift}"
  }

  @DiagsBuilder func queuingInitial(_ inputs: [String]) -> [Diagnostic.Message] {
    for input in inputs {
      "Incremental compilation: Queuing (initial):  {compile: \(input).o <= \(input).swift}"
    }
  }
  @DiagsBuilder func queuingInitial(_ inputs: String...) -> [Diagnostic.Message] {
    queuingInitial(inputs)
  }

  @DiagsBuilder func queuingBecauseInitial(_ input: String) -> [Diagnostic.Message] {
    "Incremental compilation: Queuing because of the initial set:  {compile: \(input).o <= \(input).swift}"
  }

  @DiagsBuilder func queuingLater(_ inputs: [String]) -> [Diagnostic.Message] {
    for input in inputs {
      "Incremental compilation: Queuing because of dependencies discovered later:  {compile: \(input).o <= \(input).swift}"
    }
  }
  @DiagsBuilder func queuingLater(_ inputs: String...) -> [Diagnostic.Message] { queuingLater(inputs) }

  @DiagsBuilder func queuingLaterSchedInvalBatchLink(_ inputs: [String]) -> [Diagnostic.Message] {
    queuingLater(inputs)
    schedulingInvalidated(inputs)
  }
  @DiagsBuilder func queuingLaterSchedInvalBatchLink(_ inputs: String...) -> [Diagnostic.Message] {
    queuingLaterSchedInvalBatchLink(inputs)
  }


// MARK: - skipping
  @DiagsBuilder func maySkip(_ inputs: [String]) -> [Diagnostic.Message] {
    for input in inputs {
      "Incremental compilation: May skip current input:  {compile: \(input).o <= \(input).swift}"
    }
  }
  @DiagsBuilder func maySkip(_ inputs: String...) -> [Diagnostic.Message] {
    maySkip(inputs)
  }
  @DiagsBuilder func skipping(_ inputs: [String]) -> [Diagnostic.Message] {
    for input in inputs {
      "Incremental compilation: Skipping input:  {compile: \(input).o <= \(input).swift}"
    }
  }
  @DiagsBuilder func skipping(_ inputs: String...) -> [Diagnostic.Message] {
    skipping(inputs)
  }
  @DiagsBuilder func skipped(_ inputs: [String]) -> [Diagnostic.Message] {
    for input in inputs {
      "Skipped Compiling \(input).swift"
    }
  }
  @DiagsBuilder func skipped(_ inputs: String...) -> [Diagnostic.Message] {
    skipped(inputs)
  }
  @DiagsBuilder func skippingAll(_ inputs: [String]) -> [Diagnostic.Message] {
    maySkip(inputs)
    skipping(inputs)
    skippingLinking
    skipped(inputs)
  }
  @DiagsBuilder func skippingAll(_ inputs: String...) -> [Diagnostic.Message] {
    skippingAll(inputs)
  }
  @DiagsBuilder func readGraphAndSkipAll(_ inputs: [String]) -> [Diagnostic.Message] {
    readGraph
    enablingCrossModule
    skippingAll(inputs)
  }
  @DiagsBuilder func readGraphAndSkipAll(_ inputs: String...) -> [Diagnostic.Message] {
    readGraphAndSkipAll(inputs)
  }

  // MARK: - batching
  @DiagsBuilder func addingToBatch(_ inputs: [String], _ b: Int) -> [Diagnostic.Message] {
    for input in inputs {
      "Adding {compile: \(input).swift} to batch \(b)"
    }
  }
  @DiagsBuilder func formingBatch(_ inputs: [String]) -> [Diagnostic.Message] {
    "Forming batch job from \(inputs.count) constituents: \(inputs.map{$0 + ".swift"}.joined(separator: ", "))"
  }
  @DiagsBuilder func formingBatch(_ inputs: String...) -> [Diagnostic.Message] {
    formingBatch(inputs)
  }
  @DiagsBuilder func foundBatchableJobs(_ jobCount: Int) -> [Diagnostic.Message] {
    // Omitting the "s" from "jobs" works for either 1 or many, since
    // the verifier does prefix matching.
    "Found \(jobCount) batchable job"
  }
  @DiagsBuilder var formingOneBatch: [Diagnostic.Message] { "Forming into 1 batch"}

  @DiagsBuilder func findingAndFormingBatch(_ jobCount: Int) -> [Diagnostic.Message] {
    foundBatchableJobs(jobCount); formingOneBatch
  }
  @DiagsBuilder func addingToBatchThenForming(_ inputs: [String]) -> [Diagnostic.Message] {
    addingToBatch(inputs, 0); formingBatch(inputs)
  }
  @DiagsBuilder func addingToBatchThenForming(_ inputs: String...) -> [Diagnostic.Message] {
    addingToBatchThenForming(inputs)
 }

  // MARK: - compiling
  @DiagsBuilder func starting(_ inputs: [String]) -> [Diagnostic.Message] {
     "Starting Compiling \(inputs.map{$0 + ".swift"}.joined(separator: ", "))"
  }
  @DiagsBuilder func finished(_ inputs: [String]) -> [Diagnostic.Message] {
     "Finished Compiling \(inputs.map{$0 + ".swift"}.joined(separator: ", "))"
  }
  @DiagsBuilder func compiling(_ inputs: [String]) -> [Diagnostic.Message] {
    starting(inputs); finished(inputs)
  }
  @DiagsBuilder func compiling(_ inputs: String...) -> [Diagnostic.Message] {
    compiling(inputs)
  }

// MARK: - batching and compiling
  @DiagsBuilder func findingBatchingCompiling(_ inputs: [String]) -> [Diagnostic.Message] {
    findingAndFormingBatch(inputs.count)
    addingToBatchThenForming(inputs)
    compiling(inputs)
  }
  @DiagsBuilder func findingBatchingCompiling(_ inputs: String...) -> [Diagnostic.Message] {
    findingBatchingCompiling(inputs)
  }

  // MARK: - linking
  @DiagsBuilder var schedulingPostCompileJobs: [Diagnostic.Message] {
    "Incremental compilation: Scheduling all post-compile jobs because something was compiled"
  }
  @DiagsBuilder var startingLinking: [Diagnostic.Message] { "Starting Linking theModule" }

  @DiagsBuilder var finishedLinking: [Diagnostic.Message] { "Finished Linking theModule" }

  @DiagsBuilder var skippingLinking: [Diagnostic.Message] {
    "Incremental compilation: Skipping job: Linking theModule; oldest output is current"
  }
  @DiagsBuilder var schedLinking: [Diagnostic.Message] { schedulingPostCompileJobs; linking }

  @DiagsBuilder var linking: [Diagnostic.Message] { startingLinking; finishedLinking}

  // MARK: - autolinking
  @DiagsBuilder func queuingExtractingAutolink(_ module: String) -> [Diagnostic.Message] {
    "Incremental compilation: Queuing Extracting autolink information for module \(module)"
  }
  @DiagsBuilder func startingExtractingAutolink(_ module: String) -> [Diagnostic.Message] {
    "Starting Extracting autolink information for module \(module)"
  }
  @DiagsBuilder func finishedExtractingAutolink(_ module: String) -> [Diagnostic.Message] {
    "Finished Extracting autolink information for module \(module)"
  }
  @DiagsBuilder func extractingAutolink(_ module: String) -> [Diagnostic.Message] {
    startingExtractingAutolink(module)
    finishedExtractingAutolink(module)
  }
}

// MARK: - trace building
@resultBuilder fileprivate enum TraceBuilder {
  static func buildBlock(_ components: TraceStep...) -> String {
    // Omit "Incremental compilation: Traced: " prefix because depending on
    // hash table iteration order "interface of source file from *.swiftdeps in *.swift ->"
    // may occur first. Since the tests do substring matching, this will work.
    "\(components.map {$0.messagePart}.joined(separator: " -> "))"
  }
}

fileprivate struct TraceStep {
  let messagePart: String

  init(_ aspect: DependencyKey.DeclAspect, sourceFileProvide source: String) {
    self.init(aspect, sourceFileProvide: source, input: source)
  }
  init(_ aspect: DependencyKey.DeclAspect, sourceFileProvide source: String, input: String?) {
    self.init(aspect, input: input) { t in
        .sourceFileProvide(name: "\(source).swiftdeps".intern(in: t))
    }
  }
  init(_ aspect: DependencyKey.DeclAspect, topLevel name: String, input: String) {
    self.init(aspect, input: input) { t in
        .topLevel(name: name.intern(in: t))
    }
  }
  private init(_ aspect: DependencyKey.DeclAspect,
       input: String?,
       _ createDesignator: (InternedStringTable) -> DependencyKey.Designator
) {
    self.messagePart = MockIncrementalCompilationSynchronizer.withInternedStringTable { t in
      let key = DependencyKey(aspect: aspect, designator: createDesignator(t))
      let inputPart = input.map {" in \($0).swift"} ?? ""
      return "\(key.description(in: t))\(inputPart)"
    }
  }
}
