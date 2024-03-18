//===------- ExplicitModuleBuildTests.swift - Swift Driver Tests ----------===//
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

@_spi(Testing) import SwiftDriver
import SwiftDriverExecution
import TSCBasic
import XCTest
import TestUtilities

private var testInputsPath: AbsolutePath {
  get throws {
    var root: AbsolutePath = try AbsolutePath(validating: #file)
    while root.basename != "Tests" {
      root = root.parentDirectory
    }
    return root.parentDirectory.appending(component: "TestInputs")
  }
}

/// Check that an explicit module build job contains expected inputs and options
private func checkExplicitModuleBuildJob(job: Job,
                                         moduleId: ModuleDependencyId,
                                         dependencyGraph: InterModuleDependencyGraph)
throws {
  let moduleInfo = try dependencyGraph.moduleInfo(of: moduleId)
  switch moduleInfo.details {
    case .swift(let swiftModuleDetails):
      XCTAssertTrue(job.commandLine.contains(.flag(String("-disable-implicit-swift-modules"))))
      let moduleInterfacePath =
        TypedVirtualPath(file: swiftModuleDetails.moduleInterfacePath!.path,
                         type: .swiftInterface)
      XCTAssertEqual(job.kind, .compileModuleFromInterface)
      XCTAssertTrue(job.inputs.contains(moduleInterfacePath))
      if let compiledCandidateList = swiftModuleDetails.compiledModuleCandidates {
        for compiledCandidate in compiledCandidateList {
          let candidatePath = compiledCandidate.path
          let typedCandidatePath = TypedVirtualPath(file: candidatePath,
                                                    type: .swiftModule)
          XCTAssertTrue(job.inputs.contains(typedCandidatePath))
          XCTAssertTrue(job.commandLine.contains(.flag(VirtualPath.lookup(candidatePath).description)))
        }
        XCTAssertTrue(job.commandLine.filter {$0 == .flag("-candidate-module-file")}.count == compiledCandidateList.count)
      }
    case .clang(_):
      XCTAssertEqual(job.kind, .generatePCM)
      XCTAssertEqual(job.description, "Compiling Clang module \(moduleId.moduleName)")
    case .swiftPrebuiltExternal(_):
      XCTFail("Unexpected prebuilt external module dependency found.")
    case .swiftPlaceholder(_):
      XCTFail("Placeholder dependency found.")
  }
  // Ensure the frontend was prohibited from doing implicit module builds
  XCTAssertTrue(job.commandLine.contains(.flag(String("-fno-implicit-modules"))))
  try checkExplicitModuleBuildJobDependencies(job: job,
                                              moduleInfo: moduleInfo,
                                              dependencyGraph: dependencyGraph)
}

/// Checks that the build job for the specified module contains the required options and inputs
/// to build all of its dependencies explicitly
private func checkExplicitModuleBuildJobDependencies(job: Job,
                                                     moduleInfo : ModuleInfo,
                                                     dependencyGraph: InterModuleDependencyGraph
) throws {
  let validateSwiftCommandLineDependency: (ModuleDependencyId, ModuleInfo) -> Void = { dependencyId, dependencyInfo in
    let inputModulePath = dependencyInfo.modulePath.path
    XCTAssertTrue(job.inputs.contains(TypedVirtualPath(file: inputModulePath, type: .swiftModule)))
    XCTAssertTrue(job.commandLine.contains(
      .flag(String("-swift-module-file=\(dependencyId.moduleName)=\(inputModulePath.description)"))))
  }

  let validateClangCommandLineDependency: (ModuleDependencyId,
                                           ModuleInfo,
                                           ClangModuleDetails) -> Void = { dependencyId, dependencyInfo, clangDependencyDetails  in
    let clangDependencyModulePathString = dependencyInfo.modulePath.path
    let clangDependencyModulePath =
      TypedVirtualPath(file: clangDependencyModulePathString, type: .pcm)
    XCTAssertTrue(job.inputs.contains(clangDependencyModulePath))
    XCTAssertTrue(job.commandLine.contains(
      .flag(String("-fmodule-file=\(dependencyId.moduleName)=\(clangDependencyModulePathString)"))))
    XCTAssertTrue(job.commandLine.contains(
      .flag(String("-fmodule-map-file=\(clangDependencyDetails.moduleMapPath.path.description)"))))
  }

  for dependencyId in moduleInfo.directDependencies! {
    let dependencyInfo = try dependencyGraph.moduleInfo(of: dependencyId)
    switch dependencyInfo.details {
      case .swift(_):
        fallthrough
      case .swiftPrebuiltExternal(_):
        validateSwiftCommandLineDependency(dependencyId, dependencyInfo)
      case .clang(let clangDependencyDetails):
        validateClangCommandLineDependency(dependencyId, dependencyInfo, clangDependencyDetails)
      case .swiftPlaceholder(_):
        XCTFail("Placeholder dependency found.")
    }

    // Ensure all transitive dependencies got added as well.
    for transitiveDependencyId in dependencyInfo.directDependencies! {
      try checkExplicitModuleBuildJobDependencies(job: job,
                                                  moduleInfo: try dependencyGraph.moduleInfo(of: transitiveDependencyId),
                                                  dependencyGraph: dependencyGraph)

    }
  }
}

/// Test that for the given JSON module dependency graph, valid jobs are generated
final class ExplicitModuleBuildTests: XCTestCase {
  func testModuleDependencyBuildCommandGeneration() throws {
    do {
      var driver = try Driver(args: ["swiftc", "-explicit-module-build",
                                     "-module-name", "testModuleDependencyBuildCommandGeneration",
                                     "test.swift"])
      let moduleDependencyGraph =
            try JSONDecoder().decode(
              InterModuleDependencyGraph.self,
              from: ModuleDependenciesInputs.fastDependencyScannerOutput.data(using: .utf8)!)
      driver.explicitDependencyBuildPlanner =
        try ExplicitDependencyBuildPlanner(dependencyGraph: moduleDependencyGraph,
                                           toolchain: driver.toolchain,
                                           dependencyOracle: driver.interModuleDependencyOracle)
      let modulePrebuildJobs =
        try driver.explicitDependencyBuildPlanner!.generateExplicitModuleDependenciesBuildJobs()
      XCTAssertEqual(modulePrebuildJobs.count, 4)
      for job in modulePrebuildJobs {
        XCTAssertEqual(job.outputs.count, 1)
        XCTAssertFalse(driver.isExplicitMainModuleJob(job: job))

        switch (job.outputs[0].file) {
          case .relative(try .init(validating: "SwiftShims.pcm")):
            try checkExplicitModuleBuildJob(job: job,
                                            moduleId: .clang("SwiftShims"),
                                            dependencyGraph: moduleDependencyGraph)
          case .relative(try .init(validating: "c_simd.pcm")):
            try checkExplicitModuleBuildJob(job: job,
                                            moduleId: .clang("c_simd"),
                                            dependencyGraph: moduleDependencyGraph)
          case .relative(try .init(validating: "Swift.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job,
                                            moduleId: .swift("Swift"),
                                            dependencyGraph: moduleDependencyGraph)
          case .relative(try .init(validating: "_Concurrency.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job,
                                            moduleId: .swift("_Concurrency"),
                                            dependencyGraph: moduleDependencyGraph)
          case .relative(try .init(validating: "_StringProcessing.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job,
                                            moduleId: .swift("_StringProcessing"),
                                            dependencyGraph: moduleDependencyGraph)
          case .relative(try .init(validating: "SwiftOnoneSupport.swiftmodule")):
            try checkExplicitModuleBuildJob(job: job,
                                            moduleId: .swift("SwiftOnoneSupport"),
                                            dependencyGraph: moduleDependencyGraph)
          default:
            XCTFail("Unexpected module dependency build job output: \(job.outputs[0].file)")
        }
      }
    }
  }

  func testModuleDependencyBuildCommandGenerationWithExternalFramework() throws {
    do {
      let externalDetails: ExternalTargetModuleDetailsMap =
            [.swiftPrebuiltExternal("A"): ExternalTargetModuleDetails(path: try AbsolutePath(validating: "/tmp/A.swiftmodule"),
                                                                      isFramework: true),
             .swiftPrebuiltExternal("K"): ExternalTargetModuleDetails(path: try AbsolutePath(validating: "/tmp/K.swiftmodule"),
                                                                       isFramework: true),
             .swiftPrebuiltExternal("simpleTestModule"): ExternalTargetModuleDetails(path: try AbsolutePath(validating: "/tmp/simpleTestModule.swiftmodule"),
                                                                                     isFramework: true)]
      var driver = try Driver(args: ["swiftc", "-explicit-module-build",
                                     "-module-name", "simpleTestModule",
                                     "test.swift"])
      var moduleDependencyGraph =
            try JSONDecoder().decode(
              InterModuleDependencyGraph.self,
              from: ModuleDependenciesInputs.simpleDependencyGraphInput.data(using: .utf8)!)
      // Key part of this test, using the external info to generate dependency pre-build jobs
      try moduleDependencyGraph.resolveExternalDependencies(for: externalDetails)

      // Ensure the main module was not overriden by an external dependency
      XCTAssertNotNil(moduleDependencyGraph.modules[.swift("simpleTestModule")])

      // Ensure the "K" module's framework status got resolved via `externalDetails`
      guard case .swiftPrebuiltExternal(let kPrebuiltDetails) = moduleDependencyGraph.modules[.swiftPrebuiltExternal("K")]?.details else {
        XCTFail("Expected prebuilt module details for module \"K\"")
        return
      }
      XCTAssertTrue(kPrebuiltDetails.isFramework)
      let jobsInPhases = try driver.computeJobsForPhasedStandardBuild(with: moduleDependencyGraph)
      let job = try XCTUnwrap(jobsInPhases.allJobs.first(where: { $0.kind == .compile }))
      // Load the dependency JSON and verify this dependency was encoded correctly
      let explicitDepsFlag =
        SwiftDriver.Job.ArgTemplate.flag(String("-explicit-swift-module-map-file"))
      XCTAssert(job.commandLine.contains(explicitDepsFlag))
      let jsonDepsPathIndex = job.commandLine.firstIndex(of: explicitDepsFlag)
      let jsonDepsPathArg = job.commandLine[jsonDepsPathIndex! + 1]
      guard case .path(let jsonDepsPath) = jsonDepsPathArg else {
        XCTFail("No JSON dependency file path found.")
        return
      }
      guard case let .temporaryWithKnownContents(_, contents) = jsonDepsPath else {
        XCTFail("Unexpected path type")
        return
      }
      let dependencyInfoList = try JSONDecoder().decode(Array<SwiftModuleArtifactInfo>.self,
                                                    from: contents)
      XCTAssertEqual(dependencyInfoList.count, 2)
      let dependencyArtifacts =
        dependencyInfoList.first(where:{ $0.moduleName == "A" })!
      // Ensure this is a framework, as specified by the externalDetails above.
      XCTAssertEqual(dependencyArtifacts.isFramework, true)
    }
  }

  func testModuleDependencyBuildCommandUniqueDepFile() throws {
    try withTemporaryDirectory { path in
      let source0 = path.appending(component: "testModuleDependencyBuildCommandUniqueDepFile1.swift")
      let source1 = path.appending(component: "testModuleDependencyBuildCommandUniqueDepFile2.swift")
      try localFileSystem.writeFileContents(source0, bytes:
        """
        import C;
        """
      )
      try localFileSystem.writeFileContents(source1, bytes:
        """
        import G;
        """
      )

      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let bridgingHeaderpath: AbsolutePath =
          cHeadersPath.appending(component: "Bridging.h")
      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try Driver(args: ["swiftc",
                                     "-target", "x86_64-apple-macosx11.0",
                                     "-I", cHeadersPath.nativePathString(escaped: true),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                     "-explicit-module-build",
                                     "-import-objc-header", bridgingHeaderpath.nativePathString(escaped: true),
                                     source0.nativePathString(escaped: true),
                                     source1.nativePathString(escaped: true)] + sdkArgumentsForTesting)

      let jobs = try driver.planBuild()
      let compileJobs = jobs.filter({ $0.kind == .compile })
      XCTAssertEqual(compileJobs.count, 2)
      let compileJob0 = compileJobs[0]
      let compileJob1 = compileJobs[1]
      let explicitDepsFlag = SwiftDriver.Job.ArgTemplate.flag(String("-explicit-swift-module-map-file"))
      XCTAssert(compileJob0.commandLine.contains(explicitDepsFlag))
      XCTAssert(compileJob1.commandLine.contains(explicitDepsFlag))
      let jsonDeps0PathIndex = compileJob0.commandLine.firstIndex(of: explicitDepsFlag)
      let jsonDeps0PathArg = compileJob0.commandLine[jsonDeps0PathIndex! + 1]
      let jsonDeps1PathIndex = compileJob1.commandLine.firstIndex(of: explicitDepsFlag)
      let jsonDeps1PathArg = compileJob1.commandLine[jsonDeps1PathIndex! + 1]
      XCTAssertEqual(jsonDeps0PathArg, jsonDeps1PathArg)
    }
  }

  private func pathMatchesSwiftModule(path: VirtualPath, _ name: String) -> Bool {
    return path.basenameWithoutExt.starts(with: "\(name)-") &&
           path.extension! == FileType.swiftModule.rawValue
  }

  /// Test generation of explicit module build jobs for dependency modules when the driver
  /// is invoked with -explicit-module-build
  func testExplicitModuleBuildJobs() throws {
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testExplicitModuleBuildJobs.swift")
      try localFileSystem.writeFileContents(main, bytes:
        """
        import C;\
        import E;\
        import G;
        """
      )

      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let bridgingHeaderpath: AbsolutePath =
          cHeadersPath.appending(component: "Bridging.h")
      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try Driver(args: ["swiftc",
                                     "-target", "x86_64-apple-macosx11.0",
                                     "-I", cHeadersPath.nativePathString(escaped: true),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                     "-explicit-module-build",
                                     "-import-objc-header", bridgingHeaderpath.nativePathString(escaped: true),
                                     main.nativePathString(escaped: true)] + sdkArgumentsForTesting)

      let jobs = try driver.planBuild()
      // Figure out which Triples to use.
      let dependencyGraph = try driver.gatherModuleDependencies()
      let mainModuleInfo = try dependencyGraph.moduleInfo(of: .swift("testExplicitModuleBuildJobs"))
      guard case .swift(_) = mainModuleInfo.details else {
        XCTFail("Main module does not have Swift details field")
        return
      }

      for job in jobs {
        XCTAssertEqual(job.outputs.count, 1)
        let outputFilePath = job.outputs[0].file

        // Swift dependencies
        if outputFilePath.extension != nil,
           outputFilePath.extension! == FileType.swiftModule.rawValue {
          if pathMatchesSwiftModule(path: outputFilePath, "A") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift("A"),
                                            dependencyGraph: dependencyGraph)
          } else if pathMatchesSwiftModule(path: outputFilePath, "E") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift("E"),
                                            dependencyGraph: dependencyGraph)
          } else if pathMatchesSwiftModule(path: outputFilePath, "G") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift("G"),
                                            dependencyGraph: dependencyGraph)
          } else if pathMatchesSwiftModule(path: outputFilePath, "Swift") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift("Swift"),
                                            dependencyGraph: dependencyGraph)
          } else if pathMatchesSwiftModule(path: outputFilePath, "_Concurrency") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift("_Concurrency"),
                                            dependencyGraph: dependencyGraph)
          } else if pathMatchesSwiftModule(path: outputFilePath, "_StringProcessing") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift("_StringProcessing"),
                                            dependencyGraph: dependencyGraph)
          } else if pathMatchesSwiftModule(path: outputFilePath, "SwiftOnoneSupport") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift("SwiftOnoneSupport"),
                                            dependencyGraph: dependencyGraph)
          }
        // Clang Dependencies
        } else if let outputExtension = outputFilePath.extension,
                  outputExtension == FileType.pcm.rawValue {
          let relativeOutputPathFileName = outputFilePath.basename
          if relativeOutputPathFileName.starts(with: "A-") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang("A"),
                                            dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "B-") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang("B"),
                                            dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "C-") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang("C"),
                                            dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "G-") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang("G"),
                                            dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "F-") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang("F"),
                                            dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "SwiftShims-") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang("SwiftShims"),
                                            dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "_SwiftConcurrencyShims-") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang("_SwiftConcurrencyShims"),
                                            dependencyGraph: dependencyGraph)
          }
          else {
            XCTFail("Unexpected module dependency build job output: \(outputFilePath)")
          }
        } else {
          switch (outputFilePath) {
            case .relative(try .init(validating: "testExplicitModuleBuildJobs")):
              XCTAssertTrue(driver.isExplicitMainModuleJob(job: job))
              XCTAssertEqual(job.kind, .link)
            case .temporary(_):
              let baseName = "testExplicitModuleBuildJobs"
              XCTAssertTrue(matchTemporary(outputFilePath, basename: baseName, fileExtension: "o") ||
                            matchTemporary(outputFilePath, basename: baseName, fileExtension: "autolink") ||
                            matchTemporary(outputFilePath, basename: "Bridging-", fileExtension: "pch"))
            default:
              XCTFail("Unexpected module dependency build job output: \(outputFilePath)")
          }
        }
      }
    }
  }

  /// Test generation of explicit module build jobs for dependency modules when the driver
  /// is invoked with -explicit-module-build, -verify-emitted-module-interface and -enable-library-evolution.
  func testExplicitModuleVerifyInterfaceJobs() throws {
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testExplicitModuleVerifyInterfaceJobs.swift")
      try localFileSystem.writeFileContents(main) {
        $0.send("import C;import E;import G;")
      }

      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")
      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let swiftInterfacePath: AbsolutePath = path.appending(component: "testExplicitModuleVerifyInterfaceJobs.swiftinterface")
      let privateSwiftInterfacePath: AbsolutePath = path.appending(component: "testExplicitModuleVerifyInterfaceJobs.private.swiftinterface")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try Driver(args: ["swiftc",
                                     "-target", "x86_64-apple-macosx11.0",
                                     "-I", cHeadersPath.nativePathString(escaped: true),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                     "-emit-module-interface-path", swiftInterfacePath.nativePathString(escaped: true),
                                     "-emit-private-module-interface-path", privateSwiftInterfacePath.nativePathString(escaped: true),
                                     "-explicit-module-build", "-verify-emitted-module-interface",
                                     "-enable-library-evolution",
                                     main.nativePathString(escaped: true)] + sdkArgumentsForTesting)

      guard driver.supportExplicitModuleVerifyInterface() else {
        throw XCTSkip("-typecheck-module-from-interface doesn't support explicit build.")
      }
      let jobs = try driver.planBuild()
      // Figure out which Triples to use.
      let dependencyGraph = try driver.gatherModuleDependencies()
      let mainModuleInfo = try dependencyGraph.moduleInfo(of: .swift("testExplicitModuleVerifyInterfaceJobs"))
      guard case .swift(_) = mainModuleInfo.details else {
        XCTFail("Main module does not have Swift details field")
        return
      }

      for job in jobs {
        if (job.outputs.count == 0) {
          // This is the verify module job as it should be the only job scheduled to have no output.
          XCTAssertTrue(job.kind == .verifyModuleInterface)
          // Check the explicit module flags exists.
          XCTAssertTrue(job.commandLine.contains(.flag(String("-explicit-interface-module-build"))))
          XCTAssertTrue(job.commandLine.contains(.flag(String("-explicit-swift-module-map-file"))))
          XCTAssertTrue(job.commandLine.contains(.flag(String("-disable-implicit-swift-modules"))))
          continue
        }
        let outputFilePath = job.outputs[0].file

        // Swift dependencies
        if outputFilePath.extension != nil,
           outputFilePath.extension! == FileType.swiftModule.rawValue {
          if pathMatchesSwiftModule(path: outputFilePath, "A") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift("A"),
                                            dependencyGraph: dependencyGraph)
          } else if pathMatchesSwiftModule(path: outputFilePath, "E") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift("E"),
                                            dependencyGraph: dependencyGraph)
          } else if pathMatchesSwiftModule(path: outputFilePath, "G") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift("G"),
                                            dependencyGraph: dependencyGraph)
          } else if pathMatchesSwiftModule(path: outputFilePath, "Swift") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift("Swift"),
                                            dependencyGraph: dependencyGraph)
          } else if pathMatchesSwiftModule(path: outputFilePath, "_Concurrency") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift("_Concurrency"),
                                            dependencyGraph: dependencyGraph)
          } else if pathMatchesSwiftModule(path: outputFilePath, "_StringProcessing") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift("_StringProcessing"),
                                            dependencyGraph: dependencyGraph)
          } else if pathMatchesSwiftModule(path: outputFilePath, "SwiftOnoneSupport") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift("SwiftOnoneSupport"),
                                            dependencyGraph: dependencyGraph)
          }
        // Clang Dependencies
        } else if let outputExtension = outputFilePath.extension,
                  outputExtension == FileType.pcm.rawValue {
          let relativeOutputPathFileName = outputFilePath.basename
          if relativeOutputPathFileName.starts(with: "A-") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang("A"),
                                            dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "B-") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang("B"),
                                            dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "C-") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang("C"),
                                            dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "G-") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang("G"),
                                            dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "F-") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang("F"),
                                            dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "SwiftShims-") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang("SwiftShims"),
                                            dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "_SwiftConcurrencyShims-") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang("_SwiftConcurrencyShims"),
                                            dependencyGraph: dependencyGraph)
          }
          else {
            XCTFail("Unexpected module dependency build job output: \(outputFilePath)")
          }
        } else {
          switch (outputFilePath) {
            case .relative(try .init(validating: "testExplicitModuleVerifyInterfaceJobs")):
              XCTAssertTrue(driver.isExplicitMainModuleJob(job: job))
              XCTAssertEqual(job.kind, .link)
            case .temporary(_):
              let baseName = "testExplicitModuleVerifyInterfaceJobs"
              XCTAssertTrue(matchTemporary(outputFilePath, basename: baseName, fileExtension: "o") ||
                            matchTemporary(outputFilePath, basename: baseName, fileExtension: "autolink"))
            default:
              XCTFail("Unexpected module dependency build job output: \(outputFilePath)")
          }
        }
      }
    }
  }

  /// Test generation of explicit module build jobs for dependency modules when the driver
  /// is invoked with -explicit-module-build and -pch-output-dir
  func testExplicitModuleBuildPCHOutputJobs() throws {
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testExplicitModuleBuildPCHOutputJobs.swift")
      try localFileSystem.writeFileContents(main, bytes:
        """
        import C;\
        import E;\
        import G;
        """
      )

      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")      
      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let bridgingHeaderpath: AbsolutePath =
          cHeadersPath.appending(component: "Bridging.h")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      let pchOutputDir: AbsolutePath = path
      var driver = try Driver(args: ["swiftc",
                                     "-target", "x86_64-apple-macosx11.0",
                                     "-I", cHeadersPath.nativePathString(escaped: true),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                     "-explicit-module-build",
                                     "-import-objc-header", bridgingHeaderpath.nativePathString(escaped: true),
                                     "-pch-output-dir", pchOutputDir.nativePathString(escaped: true),
                                     main.nativePathString(escaped: true)] + sdkArgumentsForTesting)

      let jobs = try driver.planBuild()
      // Figure out which Triples to use.
      let dependencyGraph = try driver.gatherModuleDependencies()
      let mainModuleInfo = try dependencyGraph.moduleInfo(of: .swift("testExplicitModuleBuildPCHOutputJobs"))
      guard case .swift(_) = mainModuleInfo.details else {
        XCTFail("Main module does not have Swift details field")
        return
      }

      for job in jobs {
        XCTAssertEqual(job.outputs.count, 1)
        let outputFilePath = job.outputs[0].file

        // Swift dependencies
        if outputFilePath.extension != nil,
           outputFilePath.extension! == FileType.swiftModule.rawValue {
          if pathMatchesSwiftModule(path: outputFilePath, "A") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift("A"),
                                            dependencyGraph: dependencyGraph)
          } else if pathMatchesSwiftModule(path: outputFilePath, "E") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift("E"),
                                            dependencyGraph: dependencyGraph)
          } else if pathMatchesSwiftModule(path: outputFilePath, "G") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift("G"),
                                            dependencyGraph: dependencyGraph)
          } else if pathMatchesSwiftModule(path: outputFilePath, "Swift") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift("Swift"),
                                            dependencyGraph: dependencyGraph)
          } else if pathMatchesSwiftModule(path: outputFilePath, "_Concurrency") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift("_Concurrency"),
                                            dependencyGraph: dependencyGraph)
          } else if pathMatchesSwiftModule(path: outputFilePath, "_StringProcessing") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift("_StringProcessing"),
                                            dependencyGraph: dependencyGraph)
          } else if pathMatchesSwiftModule(path: outputFilePath, "SwiftOnoneSupport") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift("SwiftOnoneSupport"),
                                            dependencyGraph: dependencyGraph)
          }
        // Clang Dependencies
        } else if let outputExtension = outputFilePath.extension,
                  outputExtension == FileType.pcm.rawValue {
          let relativeOutputPathFileName = outputFilePath.basename
          if relativeOutputPathFileName.starts(with: "A-") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang("A"),
                                            dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "B-") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang("B"),
                                            dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "C-") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang("C"),
                                            dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "G-") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang("G"),
                                            dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "F-") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang("F"),
                                            dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "SwiftShims-") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang("SwiftShims"),
                                            dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "_SwiftConcurrencyShims-") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang("_SwiftConcurrencyShims"),
                                            dependencyGraph: dependencyGraph)
          }
          else {
            XCTFail("Unexpected module dependency build job output: \(outputFilePath)")
          }
        // Bridging header
        } else if let outputExtension = outputFilePath.extension,
                  outputExtension == FileType.pch.rawValue {
          switch (outputFilePath) {
            case .absolute:
              // pch output is a computed absolute path.
              XCTAssertFalse(job.commandLine.contains("-pch-output-dir"))
            default:
              XCTFail("Unexpected module dependency build job output: \(outputFilePath)")
          }
        } else {
          // Check we don't use `-pch-output-dir` anymore during main module job.
          XCTAssertFalse(job.commandLine.contains("-pch-output-dir"))
          switch (outputFilePath) {
            case .relative(try .init(validating: "testExplicitModuleBuildPCHOutputJobs")):
              XCTAssertTrue(driver.isExplicitMainModuleJob(job: job))
              XCTAssertEqual(job.kind, .link)
            case .temporary(_):
              let baseName = "testExplicitModuleBuildPCHOutputJobs"
              XCTAssertTrue(matchTemporary(outputFilePath, basename: baseName, fileExtension: "o") ||
                            matchTemporary(outputFilePath, basename: baseName, fileExtension: "autolink"))
            default:
              XCTFail("Unexpected module dependency build job output: \(outputFilePath)")
          }
        }
      }
    }
  }

  func testImmediateModeExplicitModuleBuild() throws {
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testExplicitModuleBuildJobs.swift")
      try localFileSystem.writeFileContents(main, bytes: "import C\n")

      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try Driver(args: ["swift",
                                     "-target", "x86_64-apple-macosx11.0",
                                     "-I", cHeadersPath.nativePathString(escaped: true),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                     "-explicit-module-build",
                                     main.nativePathString(escaped: true)] + sdkArgumentsForTesting)

      let jobs = try driver.planBuild()

      let interpretJobs = jobs.filter { $0.kind == .interpret }
      XCTAssertEqual(interpretJobs.count, 1)
      let interpretJob = interpretJobs[0]
      XCTAssertTrue(interpretJob.requiresInPlaceExecution)
      XCTAssertTrue(interpretJob.commandLine.contains(subsequence: ["-frontend", "-interpret"]))
      //XCTAssertTrue(interpretJob.commandLine.contains("-disable-implicit-swift-modules"))
      XCTAssertTrue(interpretJob.commandLine.contains(subsequence: ["-Xcc", "-fno-implicit-modules"]))

      // Figure out which Triples to use.
      let dependencyGraph = try driver.gatherModuleDependencies()
      let mainModuleInfo = try dependencyGraph.moduleInfo(of: .swift("testExplicitModuleBuildJobs"))
      guard case .swift(_) = mainModuleInfo.details else {
        XCTFail("Main module does not have Swift details field")
        return
      }

      for job in jobs {
        guard job.kind != .interpret else { continue }
        XCTAssertEqual(job.outputs.count, 1)
        let outputFilePath = job.outputs[0].file
        // Swift dependencies
        if outputFilePath.extension != nil,
           outputFilePath.extension! == FileType.swiftModule.rawValue {
          if pathMatchesSwiftModule(path: outputFilePath, "A") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift("A"),
                                            dependencyGraph: dependencyGraph)
          } else if pathMatchesSwiftModule(path: outputFilePath, "Swift") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift("Swift"),
                                            dependencyGraph: dependencyGraph)
          } else if pathMatchesSwiftModule(path: outputFilePath, "_Concurrency") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift("_Concurrency"),
                                            dependencyGraph: dependencyGraph)
          } else if pathMatchesSwiftModule(path: outputFilePath, "_StringProcessing") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift("_StringProcessing"),
                                            dependencyGraph: dependencyGraph)
          } else if pathMatchesSwiftModule(path: outputFilePath, "SwiftOnoneSupport") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .swift("SwiftOnoneSupport"),
                                            dependencyGraph: dependencyGraph)
          }
        // Clang Dependencies
        } else if outputFilePath.extension != nil,
                  outputFilePath.extension! == FileType.pcm.rawValue {
          let relativeOutputPathFileName = outputFilePath.basename
          if relativeOutputPathFileName.starts(with: "A-") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang("A"),
                                            dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "B-") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang("B"),
                                            dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "C-") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang("C"),
                                            dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "SwiftShims-") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang("SwiftShims"),
                                            dependencyGraph: dependencyGraph)
          }
          else if relativeOutputPathFileName.starts(with: "_SwiftConcurrencyShims-") {
            try checkExplicitModuleBuildJob(job: job, moduleId: .clang("_SwiftConcurrencyShims"),
                                            dependencyGraph: dependencyGraph)
          }
          else {
            XCTFail("Unexpected module dependency build job output: \(outputFilePath)")
          }
        } else {
          switch (outputFilePath) {
            case .relative(try .init(validating: "testExplicitModuleBuildJobs")):
              XCTAssertTrue(driver.isExplicitMainModuleJob(job: job))
              XCTAssertEqual(job.kind, .link)
            case .temporary(_):
              let baseName = "testExplicitModuleBuildJobs"
              XCTAssertTrue(matchTemporary(outputFilePath, basename: baseName, fileExtension: "o") ||
                            matchTemporary(outputFilePath, basename: baseName, fileExtension: "autolink"))
            default:
              XCTFail("Unexpected module dependency build job output: \(outputFilePath)")
          }
        }
      }
    }
  }


  func testModuleAliasingPrebuiltWithScanDeps() throws {
    try withTemporaryDirectory { path in
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      let (stdLibPath, shimsPath, _, _) = try getDriverArtifactsForScanning()

      let srcBar = path.appending(component: "bar.swift")
      let moduleBarPath = path.appending(component: "Bar.swiftmodule").nativePathString(escaped: true)
      try localFileSystem.writeFileContents(srcBar, bytes: "public class KlassBar {}")

      // Create Bar.swiftmodule
      var driver = try Driver(args: ["swiftc",
                                     "-explicit-module-build",
                                     "-working-directory",
                                     path.nativePathString(escaped: true),
                                     srcBar.nativePathString(escaped: true),
                                     "-module-name",
                                     "Bar",
                                     "-emit-module",
                                     "-emit-module-path", moduleBarPath,
                                     "-module-cache-path", path.nativePathString(escaped: true),
                                     "-I", stdLibPath.nativePathString(escaped: true),
                                     "-I", shimsPath.nativePathString(escaped: true),
                              ] + sdkArgumentsForTesting,
                              env: ProcessEnv.vars)
      guard driver.isFrontendArgSupported(.moduleAlias) else {
        throw XCTSkip("Skipping: compiler does not support '-module-alias'")
      }

      let jobs = try driver.planBuild()
      try driver.run(jobs: jobs)
      XCTAssertFalse(driver.diagnosticEngine.hasErrors)
      XCTAssertTrue(FileManager.default.fileExists(atPath: moduleBarPath))

      // Foo imports Car which is mapped to the real module Bar via
      // `-module-alias Car=Bar`; it allows Car (alias) to be referenced
      // in source files, while its contents are compiled as Bar (real
      // name on disk).
      let srcFoo = path.appending(component: "Foo.swift")
      try localFileSystem.writeFileContents(srcFoo, bytes:
        """
        import Car
        func run() -> Car.KlassBar? { return nil }
        """
      )

      // Module alias with the fallback scanner (frontend scanner)
      var driverA = try Driver(args: ["swiftc",
                                      "-nonlib-dependency-scanner",
                                      "-explicit-module-build",
                                      "-working-directory",
                                      path.nativePathString(escaped: true),
                                      srcFoo.nativePathString(escaped: true),
                                      "-module-alias", "Car=Bar",
                                      "-I", path.nativePathString(escaped: true),
                                      "-I", stdLibPath.nativePathString(escaped: true),
                                      "-I", shimsPath.nativePathString(escaped: true),
                                     ] + sdkArgumentsForTesting)

      // Resulting graph should contain the real module name Bar
      let dependencyGraphA = try driverA.gatherModuleDependencies()
      XCTAssertTrue(dependencyGraphA.modules.contains { (key: ModuleDependencyId, value: ModuleInfo) in
        key.moduleName == "Bar"
      })
      XCTAssertFalse(dependencyGraphA.modules.contains { (key: ModuleDependencyId, value: ModuleInfo) in
        key.moduleName == "Car"
      })

      let plannedJobsA = try driverA.planBuild()
      XCTAssertTrue(plannedJobsA.contains { job in
        job.commandLine.contains(.flag("-module-alias")) &&
        job.commandLine.contains(.flag("Car=Bar"))
      })

      // Module alias with the default scanner (driver scanner)
      var driverB = try Driver(args: ["swiftc",
                                      "-explicit-module-build",
                                      "-working-directory",
                                      path.nativePathString(escaped: true),
                                      srcFoo.nativePathString(escaped: true),
                                      "-module-alias", "Car=Bar",
                                      "-I", path.nativePathString(escaped: true),
                                      "-I", stdLibPath.nativePathString(escaped: true),
                                      "-I", shimsPath.nativePathString(escaped: true),
                                     ] + sdkArgumentsForTesting)

      // Resulting graph should contain the real module name Bar
      let dependencyGraphB = try driverB.gatherModuleDependencies()
      XCTAssertTrue(dependencyGraphB.modules.contains { (key: ModuleDependencyId, value: ModuleInfo) in
        key.moduleName == "Bar"
      })
      XCTAssertFalse(dependencyGraphB.modules.contains { (key: ModuleDependencyId, value: ModuleInfo) in
        key.moduleName == "Car"
      })

      let plannedJobsB = try driverB.planBuild()
      XCTAssertTrue(plannedJobsB.contains { job in
        job.commandLine.contains(.flag("-module-alias")) &&
        job.commandLine.contains(.flag("Car=Bar"))
      })
    }
  }

  func testModuleAliasingInterfaceWithScanDeps() throws {
    try withTemporaryDirectory { path in
      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")

      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      let (stdLibPath, shimsPath, _, _) = try getDriverArtifactsForScanning()

      // Foo imports Car which is mapped to the real module Bar via
      // `-module-alias Car=E`; it allows Car (alias) to be referenced
      // in source files, while its contents are compiled as E (real
      // name on disk).
      let srcFoo = path.appending(component: "Foo.swift")
      try localFileSystem.writeFileContents(srcFoo, bytes: "import Car\n")

      // Module alias with the fallback scanner (frontend scanner)
      var driverA = try Driver(args: ["swiftc",
                                      "-nonlib-dependency-scanner",
                                      "-explicit-module-build",
                                      srcFoo.nativePathString(escaped: true),
                                      "-module-alias", "Car=E",
                                      "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                      "-I", stdLibPath.nativePathString(escaped: true),
                                      "-I", shimsPath.nativePathString(escaped: true),
                                     ] + sdkArgumentsForTesting)
      guard driverA.isFrontendArgSupported(.moduleAlias) else {
        throw XCTSkip("Skipping: compiler does not support '-module-alias'")
      }

      // Resulting graph should contain the real module name Bar
      let dependencyGraphA = try driverA.gatherModuleDependencies()
      XCTAssertTrue(dependencyGraphA.modules.contains { (key: ModuleDependencyId, value: ModuleInfo) in
        key.moduleName == "E"
      })
      XCTAssertFalse(dependencyGraphA.modules.contains { (key: ModuleDependencyId, value: ModuleInfo) in
        key.moduleName == "Car"
      })

      let plannedJobsA = try driverA.planBuild()
      XCTAssertTrue(plannedJobsA.contains { job in
        job.commandLine.contains(.flag("-module-alias")) &&
        job.commandLine.contains(.flag("Car=E"))
      })

      // Module alias with the default scanner (driver scanner)
      var driverB = try Driver(args: ["swiftc",
                                      "-explicit-module-build",
                                      srcFoo.nativePathString(escaped: true),
                                      "-module-alias", "Car=E",
                                      "-working-directory", path.nativePathString(escaped: true),
                                      "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                      "-I", stdLibPath.nativePathString(escaped: true),
                                      "-I", shimsPath.nativePathString(escaped: true),
                                     ] + sdkArgumentsForTesting)

      // Resulting graph should contain the real module name Bar
      let dependencyGraphB = try driverB.gatherModuleDependencies()
      XCTAssertTrue(dependencyGraphB.modules.contains { (key: ModuleDependencyId, value: ModuleInfo) in
        key.moduleName == "E"
      })
      XCTAssertFalse(dependencyGraphB.modules.contains { (key: ModuleDependencyId, value: ModuleInfo) in
        key.moduleName == "Car"
      })

      let plannedJobsB = try driverB.planBuild()
      XCTAssertTrue(plannedJobsB.contains { job in
        job.commandLine.contains(.flag("-module-alias")) &&
        job.commandLine.contains(.flag("Car=E"))
      })
    }
  }

  func testModuleAliasingWithImportPrescan() throws {
    let (_, _, toolchain, _) = try getDriverArtifactsForScanning()

    let dummyDriver = try Driver(args: ["swiftc", "-module-name", "dummyDriverCheck", "test.swift"])
    guard dummyDriver.isFrontendArgSupported(.moduleAlias) else {
      throw XCTSkip("Skipping: compiler does not support '-module-alias'")
    }

    // The dependency oracle wraps an instance of libSwiftScan and ensures thread safety across
    // queries.
    let dependencyOracle = InterModuleDependencyOracle()
    let scanLibPath = try XCTUnwrap(toolchain.lookupSwiftScanLib())
    try dependencyOracle.verifyOrCreateScannerInstance(fileSystem: localFileSystem,
                                                       swiftScanLibPath: scanLibPath)

    try withTemporaryDirectory { path in
      let main = path.appending(component: "foo.swift")
      try localFileSystem.writeFileContents(main, bytes:
        """
        import Car;\
        import Jet;
        """
      )
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      let scannerCommand = ["-scan-dependencies",
                            "-import-prescan",
                            "-module-alias",
                            "Car=Bar",
                            main.nativePathString(escaped: true)] + sdkArgumentsForTesting
      var scanDiagnostics: [ScannerDiagnosticPayload] = []
      let deps =
        try dependencyOracle.getImports(workingDirectory: path,
                                        moduleAliases: ["Car": "Bar"],
                                        commandLine: scannerCommand,
                                        diagnostics: &scanDiagnostics)

      XCTAssertTrue(deps.imports.contains("Bar"))
      XCTAssertFalse(deps.imports.contains("Car"))
      XCTAssertTrue(deps.imports.contains("Jet"))
    }
  }

  func testModuleAliasingWithExplicitBuild() throws {
    try withTemporaryDirectory { path in
      try localFileSystem.changeCurrentWorkingDirectory(to: path)
      let moduleCachePath = path.appending(component: "ModuleCache")
      try localFileSystem.createDirectory(moduleCachePath)
      let srcBar = path.appending(component: "bar.swift")
      let moduleBarPath = path.appending(component: "Bar.swiftmodule").nativePathString(escaped: true)
      try localFileSystem.writeFileContents(srcBar, bytes: "public class KlassBar {}")

      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      let (stdLibPath, shimsPath, _, _) = try getDriverArtifactsForScanning()

      var driver1 = try Driver(args: ["swiftc",
                                      "-explicit-module-build",
                                      "-module-name",
                                      "Bar",
                                      "-working-directory",
                                      path.nativePathString(escaped: true),
                                      "-emit-module",
                                      "-emit-module-path", moduleBarPath,
                                      "-module-cache-path", moduleCachePath.nativePathString(escaped: true),
                                      srcBar.nativePathString(escaped: true),
                                      "-I", stdLibPath.nativePathString(escaped: true),
                                      "-I", shimsPath.nativePathString(escaped: true),
                                     ] + sdkArgumentsForTesting,
                               env: ProcessEnv.vars)
      guard driver1.isFrontendArgSupported(.moduleAlias) else {
        throw XCTSkip("Skipping: compiler does not support '-module-alias'")
      }

      let jobs1 = try driver1.planBuild()
      try driver1.run(jobs: jobs1)
      XCTAssertFalse(driver1.diagnosticEngine.hasErrors)
      XCTAssertTrue(FileManager.default.fileExists(atPath: moduleBarPath))

      let srcFoo = path.appending(component: "foo.swift")
      let moduleFooPath = path.appending(component: "Foo.swiftmodule").nativePathString(escaped: true)

      // Module Foo imports Car but it's mapped to Bar (real name)
      // `-module-alias Car=Bar` allows Car (alias) to be referenced
      // in source files in Foo, but its contents will be compiled
      // as Bar (real name on-disk).
      try localFileSystem.writeFileContents(srcFoo, bytes:
        """
        import Car
        func run() -> Car.KlassBar? { return nil }
        """
      )
      var driver2 = try Driver(args: ["swiftc",
                                      "-I", path.nativePathString(escaped: true),
                                      "-explicit-module-build",
                                      "-module-name",
                                      "Foo",
                                      "-working-directory",
                                      path.nativePathString(escaped: true),
                                      "-emit-module",
                                      "-emit-module-path", moduleFooPath,
                                      "-module-cache-path", moduleCachePath.nativePathString(escaped: true),
                                      "-module-alias",
                                      "Car=Bar",
                                      srcFoo.nativePathString(escaped: true),
                                      "-I", stdLibPath.nativePathString(escaped: true),
                                      "-I", shimsPath.nativePathString(escaped: true),
                                      ] + sdkArgumentsForTesting,
                               env: ProcessEnv.vars)
      let jobs2 = try driver2.planBuild()
      try driver2.run(jobs: jobs2)
      XCTAssertFalse(driver2.diagnosticEngine.hasErrors)
      XCTAssertTrue(FileManager.default.fileExists(atPath: moduleFooPath))
    }
  }

  func testExplicitModuleBuildEndToEnd() throws {
    try withTemporaryDirectory { path in
      try localFileSystem.changeCurrentWorkingDirectory(to: path)
      let moduleCachePath = path.appending(component: "ModuleCache")
      try localFileSystem.createDirectory(moduleCachePath)
      let main = path.appending(component: "testExplicitModuleBuildEndToEnd.swift")
      try localFileSystem.writeFileContents(main, bytes:
        """
        import C;
        import E;
        import G;
        """
      )

      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try Driver(args: ["swiftc",
                                     "-I", cHeadersPath.nativePathString(escaped: true),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                     "-explicit-module-build", "-v",
                                     "-module-cache-path", moduleCachePath.nativePathString(escaped: true),
                                     "-working-directory", path.nativePathString(escaped: true),
                                     main.nativePathString(escaped: true)] + sdkArgumentsForTesting,
                              env: ProcessEnv.vars)
      let jobs = try driver.planBuild()
      try driver.run(jobs: jobs)
      XCTAssertFalse(driver.diagnosticEngine.hasErrors)
    }
  }

  func testBinaryFrameworkDependencyScan() throws {
    try withTemporaryDirectory { path in
      let (stdLibPath, shimsPath, toolchain, hostTriple) = try getDriverArtifactsForScanning()
      let moduleCachePath = path.appending(component: "ModuleCache")

      // Setup module to be used as dependency
      try localFileSystem.createDirectory(moduleCachePath)
      let frameworksPath = path.appending(component: "Frameworks")
      let frameworkModuleDir = frameworksPath.appending(component: "Foo.framework")
                                             .appending(component: "Modules")
                                             .appending(component: "Foo.swiftmodule")
      let frameworkModulePath =
          frameworkModuleDir.appending(component: hostTriple.archName + ".swiftmodule")
      try localFileSystem.createDirectory(frameworkModuleDir, recursive: true)
      let fooSourcePath = path.appending(component: "Foo.swift")
      try localFileSystem.writeFileContents(fooSourcePath, bytes: "public func foo() {}")

      // Setup our main test module
      let mainSourcePath = path.appending(component: "Foo.swift")
      try localFileSystem.writeFileContents(mainSourcePath, bytes: "import Foo")

      // 1. Build Foo module
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driverFoo = try Driver(args: ["swiftc",
                                        "-module-cache-path", moduleCachePath.nativePathString(escaped: true),
                                        "-module-name", "Foo",
                                        "-emit-module",
                                        "-emit-module-path",
                                        frameworkModulePath.nativePathString(escaped: true),
                                        "-working-directory",
                                        path.nativePathString(escaped: true),
                                        fooSourcePath.nativePathString(escaped: true)] + sdkArgumentsForTesting,
                                 env: ProcessEnv.vars)
      let jobs = try driverFoo.planBuild()
      try driverFoo.run(jobs: jobs)
      XCTAssertFalse(driverFoo.diagnosticEngine.hasErrors)

      // 2. Run a dependency scan to find the just-built module
      let dependencyOracle = InterModuleDependencyOracle()
      let scanLibPath = try XCTUnwrap(toolchain.lookupSwiftScanLib())
      try dependencyOracle.verifyOrCreateScannerInstance(fileSystem: localFileSystem,
                                                         swiftScanLibPath: scanLibPath)
      guard try dependencyOracle.supportsBinaryFrameworkDependencies() else {
        throw XCTSkip("libSwiftScan does not support framework binary dependency reporting.")
      }

      var driver = try Driver(args: ["swiftc",
                                     "-I", stdLibPath.nativePathString(escaped: true),
                                     "-I", shimsPath.nativePathString(escaped: true),
                                     "-F", frameworksPath.nativePathString(escaped: true),
                                     "-explicit-module-build",
                                     "-module-name", "main",
                                     "-working-directory", path.nativePathString(escaped: true),
                                     mainSourcePath.nativePathString(escaped: true)] + sdkArgumentsForTesting,
                              env: ProcessEnv.vars)
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      var scannerCommand = try driver.dependencyScannerInvocationCommand().1.map { try resolver.resolve($0) }
      if scannerCommand.first == "-frontend" {
        scannerCommand.removeFirst()
      }
      var scanDiagnostics: [ScannerDiagnosticPayload] = []
      let dependencyGraph =
          try dependencyOracle.getDependencies(workingDirectory: path,
                                               commandLine: scannerCommand,
                                               diagnostics: &scanDiagnostics)

      let fooDependencyInfo = try XCTUnwrap(dependencyGraph.modules[.swiftPrebuiltExternal("Foo")])
      guard case .swiftPrebuiltExternal(let fooDetails) = fooDependencyInfo.details else {
        XCTFail("Foo dependency module does not have Swift details field")
        return
      }

      // Ensure the dependency has been reported as a framework
      XCTAssertTrue(fooDetails.isFramework)
    }
  }

  func getStdlibShimsPaths(_ driver: Driver) throws -> (AbsolutePath, AbsolutePath) {
    let toolchainRootPath: AbsolutePath = try driver.toolchain.getToolPath(.swiftCompiler)
                                                            .parentDirectory // bin
                                                            .parentDirectory // toolchain root
    if driver.targetTriple.isDarwin {
      let executor = try SwiftDriverExecutor(diagnosticsEngine: DiagnosticsEngine(handlers: [Driver.stderrDiagnosticsHandler]),
                                             processSet: ProcessSet(),
                                             fileSystem: localFileSystem,
                                             env: ProcessEnv.vars)
      let sdkPath = try executor.checkNonZeroExit(
        args: "xcrun", "-sdk", "macosx", "--show-sdk-path").spm_chomp()
      let stdLibPath = try AbsolutePath(validating: sdkPath).appending(component: "usr")
        .appending(component: "lib")
        .appending(component: "swift")
      return (stdLibPath, stdLibPath.appending(component: "shims"))
    } else if driver.targetTriple.isWindows {
      if let sdkroot = try driver.toolchain.defaultSDKPath(driver.targetTriple) {
        return (sdkroot.appending(components: "usr", "lib", "swift", "windows"),
                sdkroot.appending(components: "usr", "lib", "swift", "shims"))
      }
      return (toolchainRootPath
                .appending(component: "lib")
                .appending(component: "swift")
                .appending(component: driver.targetTriple.osNameUnversioned),
              toolchainRootPath
                .appending(component: "lib")
                .appending(component: "swift")
                .appending(component: "shims"))
    } else {
      return (toolchainRootPath.appending(component: "lib")
                .appending(component: "swift")
                .appending(component: driver.targetTriple.osNameUnversioned),
              toolchainRootPath.appending(component: "lib")
                .appending(component: "swift")
                .appending(component: "shims"))
    }
  }

  private func getDriverArtifactsForScanning() throws -> (stdLibPath: AbsolutePath,
                                                          shimsPath: AbsolutePath,
                                                          toolchain: Toolchain,
                                                          hostTriple: Triple) {
    // Just instantiating to get at the toolchain path
    let driver = try Driver(args: ["swiftc", "-explicit-module-build",
                                   "-module-name", "testDependencyScanning",
                                   "test.swift"])
    let (stdLibPath, shimsPath) = try getStdlibShimsPaths(driver)
    XCTAssertTrue(localFileSystem.exists(stdLibPath),
                  "expected Swift StdLib at: \(stdLibPath.description)")
    XCTAssertTrue(localFileSystem.exists(shimsPath),
                  "expected Swift Shims at: \(shimsPath.description)")
    return (stdLibPath, shimsPath, driver.toolchain, driver.hostTriple)
  }

  /// Test the libSwiftScan dependency scanning (import-prescan).
  func testDependencyImportPrescan() throws {
    let (stdLibPath, shimsPath, toolchain, _) = try getDriverArtifactsForScanning()

    // The dependency oracle wraps an instance of libSwiftScan and ensures thread safety across
    // queries.
    let dependencyOracle = InterModuleDependencyOracle()
    let scanLibPath = try XCTUnwrap(toolchain.lookupSwiftScanLib())
    try dependencyOracle.verifyOrCreateScannerInstance(fileSystem: localFileSystem,
                                                       swiftScanLibPath: scanLibPath)

    // Create a simple test case.
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testDependencyScanning.swift")
      try localFileSystem.writeFileContents(main, bytes:
        """
        import C;\
        import E;\
        import G;"
        """
      )
      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      let scannerCommand = ["-scan-dependencies",
                            "-import-prescan",
                            "-I", cHeadersPath.nativePathString(escaped: true),
                            "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                            "-I", stdLibPath.nativePathString(escaped: true),
                            "-I", shimsPath.nativePathString(escaped: true),
                            main.nativePathString(escaped: true)] + sdkArgumentsForTesting
      var scanDiagnostics: [ScannerDiagnosticPayload] = []
      let imports =
        try dependencyOracle.getImports(workingDirectory: path,
                                        commandLine: scannerCommand,
                                        diagnostics: &scanDiagnostics)
      let expectedImports = ["C", "E", "G", "Swift", "SwiftOnoneSupport"]
      // Dependnig on how recent the platform we are running on, the _Concurrency module may or may not be present.
      let expectedImports2 = ["C", "E", "G", "Swift", "SwiftOnoneSupport", "_Concurrency"]
      // Dependnig on how recent the platform we are running on, the _StringProcessing module may or may not be present.
      let expectedImports3 = ["C", "E", "G", "Swift", "SwiftOnoneSupport", "_Concurrency", "_StringProcessing"]
      // Dependnig on how recent the platform we are running on, the _SwiftConcurrencyShims module may or may not be present.
      let expectedImports4 = ["C", "E", "G", "Swift", "SwiftOnoneSupport", "_Concurrency", "_StringProcessing", "_SwiftConcurrencyShims"]
      let expectedImports5 = ["C", "E", "G", "Swift", "SwiftOnoneSupport", "_Concurrency", "_SwiftConcurrencyShims"]
      XCTAssertTrue(
        Set(imports.imports) == Set(expectedImports) ||
        Set(imports.imports) == Set(expectedImports2) ||
        Set(imports.imports) == Set(expectedImports3) ||
        Set(imports.imports) == Set(expectedImports4) ||
        Set(imports.imports) == Set(expectedImports5))
    }
  }


  /// Test that the scanner invocation does not rely in response files
  func testDependencyScanningNoResponse() throws {
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testDependencyScanning.swift")
      // With a number of inputs this large, a response file should be generated
      // unless explicitly not supported, as should be the case for scan-deps.
      let lotsOfInputs = (0...700).map{"test\($0).swift"}
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try Driver(args: ["swiftc",
                                     "-explicit-module-build",
                                     "-working-directory", path.nativePathString(escaped: true),
                                     main.nativePathString(escaped: true)] + lotsOfInputs + sdkArgumentsForTesting,
                              env: ProcessEnv.vars)
      let scannerJob = try driver.dependencyScanningJob()

      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      let (args, _) = try resolver.resolveArgumentList(for: scannerJob,
                                                       useResponseFiles: .disabled)
      XCTAssertTrue(args.count > 1)
      XCTAssertFalse(args[0].hasSuffix(".resp"))
    }
  }

  /// Test that the scanner invocation does not rely on response files
  func testDependencyScanningSeparateClangScanCache() throws {
    try withTemporaryDirectory { path in
      let scannerCachePath: AbsolutePath = path.appending(component: "ClangScannerCache")
      let moduleCachePath: AbsolutePath = path.appending(component: "ModuleCache")
      let main = path.appending(component: "testDependencyScanningSeparateClangScanCache.swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try Driver(args: ["swiftc",
                                     "-explicit-module-build",
                                     "-clang-scanner-module-cache-path",
                                     scannerCachePath.nativePathString(escaped: true),
                                     "-module-cache-path",
                                     moduleCachePath.nativePathString(escaped: true),
                                     "-working-directory", path.nativePathString(escaped: true),
                                     main.nativePathString(escaped: true)] + sdkArgumentsForTesting,
                              env: ProcessEnv.vars)
      guard driver.isFrontendArgSupported(.clangScannerModuleCachePath) else {
        throw XCTSkip("Skipping: compiler does not support '-clang-scanner-module-cache-path'")
      }

      let scannerJob = try driver.dependencyScanningJob()
      XCTAssertTrue(scannerJob.commandLine.contains(subsequence: [.flag("-clang-scanner-module-cache-path"),
                                                                  .path(.absolute(scannerCachePath))]))
    }
  }

  func testDependencyScanningFailure() throws {
    let (stdlibPath, shimsPath, toolchain, _) = try getDriverArtifactsForScanning()

    // The dependency oracle wraps an instance of libSwiftScan and ensures thread safety across
    // queries.
    let dependencyOracle = InterModuleDependencyOracle()
    let scanLibPath = try XCTUnwrap(toolchain.lookupSwiftScanLib())
    try dependencyOracle.verifyOrCreateScannerInstance(fileSystem: localFileSystem,
                                                       swiftScanLibPath: scanLibPath)
    guard try dependencyOracle.supportsScannerDiagnostics() else {
      throw XCTSkip("libSwiftScan does not support diagnostics query.")
    }

    try withTemporaryDirectory { path in
      let main = path.appending(component: "testDependencyScanning.swift")
      try localFileSystem.writeFileContents(main, bytes: "import S;")

      let cHeadersPath: AbsolutePath =
      try testInputsPath.appending(component: "ExplicitModuleBuilds")
                        .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
      try testInputsPath.appending(component: "ExplicitModuleBuilds")
                        .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try Driver(args: ["swiftc",
                                     "-I", cHeadersPath.nativePathString(escaped: true),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                     "-I", stdlibPath.nativePathString(escaped: true),
                                     "-I", shimsPath.nativePathString(escaped: true),
                                     "-explicit-module-build",
                                     "-working-directory", path.nativePathString(escaped: true),
                                     "-disable-clang-target",
                                     main.nativePathString(escaped: true)] + sdkArgumentsForTesting,
                              env: ProcessEnv.vars)
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      var scannerCommand = try driver.dependencyScannerInvocationCommand().1.map { try resolver.resolve($0) }
      if scannerCommand.first == "-frontend" {
        scannerCommand.removeFirst()
      }
      var scanDiagnostics: [ScannerDiagnosticPayload] = []
      let _ =
          try dependencyOracle.getDependencies(workingDirectory: path,
                                               commandLine: scannerCommand,
                                               diagnostics: &scanDiagnostics)
      let potentialDiags: [ScannerDiagnosticPayload]?
      if try dependencyOracle.supportsPerScanDiagnostics() {
        potentialDiags = scanDiagnostics
        print("Using Per-Scan diagnostics")
      } else {
        potentialDiags = try dependencyOracle.getScannerDiagnostics()
        print("Using Scanner-Global diagnostics")
      }
      XCTAssertEqual(potentialDiags?.count, 5)
      let diags = try XCTUnwrap(potentialDiags)
      let error = diags[0]
      XCTAssertEqual(error.message, "Unable to find module dependency: 'unknown_module'")
      XCTAssertEqual(error.severity, .error)
      let noteI = diags[1]
      XCTAssertTrue(noteI.message.starts(with: "a dependency of Swift module 'I':"))
      XCTAssertEqual(noteI.severity, .note)
      let noteW = diags[2]
      XCTAssertTrue(noteW.message.starts(with: "a dependency of Swift module 'W':"))
      XCTAssertEqual(noteW.severity, .note)
      let noteS = diags[3]
      XCTAssertTrue(noteS.message.starts(with: "a dependency of Swift module 'S':"))
      XCTAssertEqual(noteS.severity, .note)
      let noteTest = diags[4]
      XCTAssertEqual(noteTest.message, "a dependency of main module 'testDependencyScanning'")
      XCTAssertEqual(noteTest.severity, .note)
    }
  }

  /// Test the libSwiftScan dependency scanning.
  func testDependencyScanning() throws {
    let (stdlibPath, shimsPath, toolchain, hostTriple) = try getDriverArtifactsForScanning()

    // The dependency oracle wraps an instance of libSwiftScan and ensures thread safety across
    // queries.
    let dependencyOracle = InterModuleDependencyOracle()
    let scanLibPath = try XCTUnwrap(toolchain.lookupSwiftScanLib())
    try dependencyOracle.verifyOrCreateScannerInstance(fileSystem: localFileSystem,
                                                       swiftScanLibPath: scanLibPath)

    // Create a simple test case.
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testDependencyScanning.swift")
      try localFileSystem.writeFileContents(main, bytes:
        """
        import C;\
        import E;\
        import G;
        """
      )

      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try Driver(args: ["swiftc",
                                     "-I", cHeadersPath.nativePathString(escaped: true),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                     "-I", stdlibPath.nativePathString(escaped: true),
                                     "-I", shimsPath.nativePathString(escaped: true),
                                     "/tmp/Foo.o",
                                     "-explicit-module-build",
                                     "-working-directory", path.nativePathString(escaped: true),
                                     "-disable-clang-target",
                                     main.nativePathString(escaped: true)] + sdkArgumentsForTesting,
                              env: ProcessEnv.vars)
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      var scannerCommand = try driver.dependencyScannerInvocationCommand().1.map { try resolver.resolve($0) }
      // We generate full swiftc -frontend -scan-dependencies invocations in order to also be
      // able to launch them as standalone jobs. Frontend's argument parser won't recognize
      // -frontend when passed directly via libSwiftScan.
      if scannerCommand.first == "-frontend" {
        scannerCommand.removeFirst()
      }

      // Ensure we do not propagate the usual PCH-handling arguments to the scanner invocation
      XCTAssertFalse(scannerCommand.contains("-pch-output-dir"))
      XCTAssertFalse(scannerCommand.contains("Foo.o"))

      // Here purely to dump diagnostic output in a reasonable fashion when things go wrong.
      let lock = NSLock()

      // Module `X` is only imported on Darwin when:
      // #if __ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__ < 110000
      let expectedNumberOfDependencies: Int
      if hostTriple.isMacOSX,
         hostTriple.version(for: .macOS) >= Triple.Version(11, 0, 0) {
        expectedNumberOfDependencies = 11
      } else if driver.targetTriple.isWindows {
        expectedNumberOfDependencies = 14
      } else {
        expectedNumberOfDependencies = 12
      }

      // Dispatch several iterations in parallel
      DispatchQueue.concurrentPerform(iterations: 20) { index in
        // Give the main modules different names
        let iterationCommand = scannerCommand + ["-module-name",
                                                 "testDependencyScanning\(index)",
                                                 // FIXME: We need to differentiate the scanning action hash,
                                                 // though the module-name above should be sufficient.
                                                 "-I/tmp/foo/bar/\(index)"]
        do {
          var scanDiagnostics: [ScannerDiagnosticPayload] = []
          let dependencyGraph =
            try dependencyOracle.getDependencies(workingDirectory: path,
                                                 commandLine: iterationCommand,
                                                 diagnostics: &scanDiagnostics)

          // The _Concurrency and _StringProcessing modules are automatically
          // imported in newer versions of the Swift compiler. If they happened to
          // be provided, adjust our expectations accordingly.
          let hasConcurrencyModule = dependencyGraph.modules.keys.contains {
            $0.moduleName == "_Concurrency"
          }
          let hasConcurrencyShimsModule = dependencyGraph.modules.keys.contains {
            $0.moduleName == "_SwiftConcurrencyShims"
          }
          let hasStringProcessingModule = dependencyGraph.modules.keys.contains {
            $0.moduleName == "_StringProcessing"
          }
          let adjustedExpectedNumberOfDependencies =
              expectedNumberOfDependencies +
              (hasConcurrencyModule ? 1 : 0) +
              (hasConcurrencyShimsModule ? 1 : 0) +
              (hasStringProcessingModule ? 1 : 0)

          if (dependencyGraph.modules.count != adjustedExpectedNumberOfDependencies) {
            lock.lock()
            print("Unexpected Dependency Scanning Result (\(dependencyGraph.modules.count) modules):")
            dependencyGraph.modules.forEach {
              print($0.key.moduleName)
            }
            lock.unlock()
          }
          XCTAssertTrue(dependencyGraph.modules.count ==
                        adjustedExpectedNumberOfDependencies)
        } catch {
          XCTFail("Unexpected error: \(error)")
        }
      }
    }
  }

  func testParallelDependencyScanningDiagnostics() throws {
    let (stdlibPath, shimsPath, toolchain, _) = try getDriverArtifactsForScanning()
    // The dependency oracle wraps an instance of libSwiftScan and ensures thread safety across
    // queries.
    let dependencyOracle = InterModuleDependencyOracle()
    let scanLibPath = try XCTUnwrap(toolchain.lookupSwiftScanLib())
    try dependencyOracle.verifyOrCreateScannerInstance(fileSystem: localFileSystem,
                                                       swiftScanLibPath: scanLibPath)
    if !(try dependencyOracle.supportsPerScanDiagnostics()) {
      throw XCTSkip("Scanner does not support per-scan diagnostics")
    }
    // Create a simple test case.
    try withTemporaryDirectory { path in
      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      let baseDriverArgs = ["swiftc",
                            "-I", cHeadersPath.nativePathString(escaped: true),
                            "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                            "-I", stdlibPath.nativePathString(escaped: true),
                            "-I", shimsPath.nativePathString(escaped: true),
                            "/tmp/Foo.o",
                            "-explicit-module-build",
                            "-working-directory", path.nativePathString(escaped: true),
                            "-disable-clang-target"] + sdkArgumentsForTesting
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      let numFiles = 10
      var files: [AbsolutePath] = []
      var drivers: [Driver] = []
      var scannerCommands: [[String]] = []
      for fileIndex in 0..<numFiles {
        files.append(path.appending(component: "testParallelDependencyScanningDiagnostics\(fileIndex).swift"))
        try localFileSystem.writeFileContents(files.last!, bytes: ByteString(encodingAsUTF8: "import UnknownModule\(fileIndex);"))
        var driver = try Driver(args: baseDriverArgs +
                                      [files.last!.nativePathString(escaped: true)] +
                                      ["-module-name","testParallelDependencyScanningDiagnostics\(fileIndex)"] +
                                       // FIXME: We need to differentiate the scanning action hash,
                                       // though the module-name above should be sufficient.
                                      ["-I/tmp/foo/bar/\(fileIndex)"],
                                env: ProcessEnv.vars)
        var scannerCommand = try driver.dependencyScannerInvocationCommand().1.map { try resolver.resolve($0) }
        if scannerCommand.first == "-frontend" {
          scannerCommand.removeFirst()
        }
        scannerCommands.append(scannerCommand)
        drivers.append(driver)
      }
      var scanDiagnostics = [[ScannerDiagnosticPayload]](repeating: [], count: numFiles)
      // Execute scans concurrently
      DispatchQueue.concurrentPerform(iterations: numFiles) { scanIndex in
        do {
          let _ =
            try dependencyOracle.getDependencies(workingDirectory: path,
                                                 commandLine: scannerCommands[scanIndex],
                                                 diagnostics: &scanDiagnostics[scanIndex])
        } catch {
          XCTFail("Unexpected error: \(error)")
        }
      }
      // Examine the results
      if try dependencyOracle.supportsPerScanDiagnostics() {
        for scanIndex in 0..<numFiles {
          let diagnostics = scanDiagnostics[scanIndex]
          XCTAssertEqual(diagnostics.count, 2)
          XCTAssertEqual(diagnostics[0].message, "Unable to find module dependency: 'UnknownModule\(scanIndex)'")
          XCTAssertEqual(diagnostics[1].message, "a dependency of main module 'testParallelDependencyScanningDiagnostics\(scanIndex)'")
        }
      } else {
        let globalDiagnostics = try dependencyOracle.getScannerDiagnostics()
        for scanIndex in 0..<numFiles {
          XCTAssertTrue(globalDiagnostics?.contains(where: {$0.message == "Unable to find module dependency: 'UnknownModule\(scanIndex)'"}))
          XCTAssertTrue(globalDiagnostics?.contains(where: {$0.message == "a dependency of main module 'testParallelDependencyScanningDiagnostics\(scanIndex)'"}))
        }
      }
    }
  }

  func testPrintingExplicitDependencyGraph() throws {
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testPrintingExplicitDependencyGraph.swift")
      try localFileSystem.writeFileContents(main, bytes:
        """
        import C;\
        import E;\
        import G;
        """
      )
      let cHeadersPath: AbsolutePath = try testInputsPath.appending(component: "ExplicitModuleBuilds").appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath = try testInputsPath.appending(component: "ExplicitModuleBuilds").appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []

      let baseCommandLine = ["swiftc",
                             "-I", cHeadersPath.nativePathString(escaped: true),
                             "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                             main.nativePathString(escaped: true)] + sdkArgumentsForTesting
      do {
        let diagnosticEngine = DiagnosticsEngine()
        var driver = try Driver(args: baseCommandLine + ["-print-explicit-dependency-graph"],
                                diagnosticsEngine: diagnosticEngine)
        let _ = try driver.planBuild()
        XCTAssertTrue(diagnosticEngine.hasErrors)
        XCTAssertEqual(diagnosticEngine.diagnostics.first?.message.data.description,
                       "'-print-explicit-dependency-graph' cannot be specified if '-explicit-module-build' is not present")
      }
      do {
        let diagnosticEngine = DiagnosticsEngine()
        var driver = try Driver(args: baseCommandLine + ["-explicit-module-build",
                                                         "-explicit-dependency-graph-format=json"],
                                diagnosticsEngine: diagnosticEngine)
        let _ = try driver.planBuild()
        XCTAssertTrue(diagnosticEngine.hasErrors)
        XCTAssertEqual(diagnosticEngine.diagnostics.first?.message.data.description,
                       "'-explicit-dependency-graph-format=' cannot be specified if '-print-explicit-dependency-graph' is not present")
      }
      do {
        let diagnosticEngine = DiagnosticsEngine()
        var driver = try Driver(args: baseCommandLine + ["-explicit-module-build",
                                                         "-print-explicit-dependency-graph",
                                                         "-explicit-dependency-graph-format=watercolor"],
                                diagnosticsEngine: diagnosticEngine)
        let _ = try driver.planBuild()
        XCTAssertTrue(diagnosticEngine.hasErrors)
        XCTAssertEqual(diagnosticEngine.diagnostics.first?.message.data.description,
                       "unsupported argument \'watercolor\' to option \'-explicit-dependency-graph-format=\'")
      }

      let _ = try withHijackedOutputStream {
        let diagnosticEngine = DiagnosticsEngine()
        var driver = try Driver(args: baseCommandLine + ["-explicit-module-build",
                                                         "-print-explicit-dependency-graph",
                                                         "-explicit-dependency-graph-format=json"],
                                diagnosticsEngine: diagnosticEngine)
        let _ = try driver.planBuild()
      }

      let output = try withHijackedOutputStream {
        let diagnosticEngine = DiagnosticsEngine()
        var driver = try Driver(args: baseCommandLine + ["-explicit-module-build",
                                                         "-print-explicit-dependency-graph",
                                                         "-explicit-dependency-graph-format=json"],
                                diagnosticsEngine: diagnosticEngine)
        let _ = try driver.planBuild()
      }
      XCTAssertTrue(output.contains("\"mainModuleName\" : \"testPrintingExplicitDependencyGraph\""))

      let output2 = try withHijackedOutputStream {
        let diagnosticEngine = DiagnosticsEngine()
        var driver = try Driver(args: baseCommandLine + ["-explicit-module-build",
                                                         "-print-explicit-dependency-graph",
                                                         "-explicit-dependency-graph-format=dot"],
                                diagnosticsEngine: diagnosticEngine)
        let _ = try driver.planBuild()
      }
      XCTAssertTrue(output2.contains("\"testPrintingExplicitDependencyGraph\" [shape=box, style=bold, color=navy"))

      let output3 = try withHijackedOutputStream {
        let diagnosticEngine = DiagnosticsEngine()
        var driver = try Driver(args: baseCommandLine + ["-explicit-module-build",
                                                         "-print-explicit-dependency-graph"],
                                diagnosticsEngine: diagnosticEngine)
        let _ = try driver.planBuild()
      }
      XCTAssertTrue(output3.contains("\"mainModuleName\" : \"testPrintingExplicitDependencyGraph\""))
    }
  }

  func testDependencyGraphDotSerialization() throws {
      let (stdlibPath, shimsPath, toolchain, _) = try getDriverArtifactsForScanning()
      let dependencyOracle = InterModuleDependencyOracle()
      let scanLibPath = try XCTUnwrap(toolchain.lookupSwiftScanLib())
      try dependencyOracle.verifyOrCreateScannerInstance(fileSystem: localFileSystem,
                                                         swiftScanLibPath: scanLibPath)
      // Create a simple test case.
      try withTemporaryDirectory { path in
        let main = path.appending(component: "testDependencyScanning.swift")
        try localFileSystem.writeFileContents(main, bytes:
          """
          import C;\
          import E;\
          import G;
          """
        )

        let cHeadersPath: AbsolutePath =
            try testInputsPath.appending(component: "ExplicitModuleBuilds")
                              .appending(component: "CHeaders")
        let swiftModuleInterfacesPath: AbsolutePath =
            try testInputsPath.appending(component: "ExplicitModuleBuilds")
                              .appending(component: "Swift")
        let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
        var driver = try Driver(args: ["swiftc",
                                       "-I", cHeadersPath.nativePathString(escaped: true),
                                       "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                       "-I", stdlibPath.nativePathString(escaped: true),
                                       "-I", shimsPath.nativePathString(escaped: true),
                                       "-explicit-module-build",
                                       "-working-directory", path.nativePathString(escaped: true),
                                       "-disable-clang-target",
                                       main.nativePathString(escaped: true)] + sdkArgumentsForTesting,
                                env: ProcessEnv.vars)
        let resolver = try ArgsResolver(fileSystem: localFileSystem)
        var scannerCommand = try driver.dependencyScannerInvocationCommand().1.map { try resolver.resolve($0) }
        if scannerCommand.first == "-frontend" {
          scannerCommand.removeFirst()
        }
        var scanDiagnostics: [ScannerDiagnosticPayload] = []
        let dependencyGraph =
          try dependencyOracle.getDependencies(workingDirectory: path,
                                               commandLine: scannerCommand,
                                               diagnostics: &scanDiagnostics)
        let serializer = DOTModuleDependencyGraphSerializer(dependencyGraph)

        let outputFile = path.appending(component: "dependency_graph.dot")
        var outputStream = try ThreadSafeOutputByteStream(LocalFileOutputByteStream(outputFile))
        serializer.writeDOT(to: &outputStream)
        outputStream.flush()
        let contents = try localFileSystem.readFileContents(outputFile).description
        XCTAssertTrue(contents.contains("\"testDependencyScanning\" [shape=box, style=bold, color=navy"))
        XCTAssertTrue(contents.contains("\"G\" [style=bold, color=orange"))
        XCTAssertTrue(contents.contains("\"E\" [style=bold, color=orange, style=filled"))
        XCTAssertTrue(contents.contains("\"C (C)\" [style=bold, color=lightskyblue, style=filled"))
        XCTAssertTrue(contents.contains("\"Swift\" [style=bold, color=orange, style=filled"))
        XCTAssertTrue(contents.contains("\"SwiftShims (C)\" [style=bold, color=lightskyblue, style=filled"))
        XCTAssertTrue(contents.contains("\"Swift\" -> \"SwiftShims (C)\" [color=black];"))
      }
  }

  /// Test the libSwiftScan dependency scanning.
  func testDependencyScanReuseCache() throws {
    let (stdlibPath, shimsPath, toolchain, _) = try getDriverArtifactsForScanning()
    try withTemporaryDirectory { path in
      let cacheSavePath = path.appending(component: "saved.moddepcache")
      let main = path.appending(component: "testDependencyScanning.swift")
      try localFileSystem.writeFileContents(main, bytes:
        """
        import C;\
        import E;\
        import G;
        """
      )

      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try Driver(args: ["swiftc",
                                     "-I", cHeadersPath.nativePathString(escaped: true),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                     "-I", stdlibPath.nativePathString(escaped: true),
                                     "-I", shimsPath.nativePathString(escaped: true),
                                     "-explicit-module-build",
                                     "-working-directory", path.nativePathString(escaped: true),
                                     "-disable-clang-target",
                                     main.nativePathString(escaped: true)] + sdkArgumentsForTesting,
                              env: ProcessEnv.vars)
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      var scannerCommand = try driver.dependencyScannerInvocationCommand().1.map { try resolver.resolve($0) }
      // We generate full swiftc -frontend -scan-dependencies invocations in order to also be
      // able to launch them as standalone jobs. Frontend's argument parser won't recognize
      // -frontend when passed directly via libSwiftScan.
      if scannerCommand.first == "-frontend" {
        scannerCommand.removeFirst()
      }

      let scanLibPath = try XCTUnwrap(toolchain.lookupSwiftScanLib())
      // Run the first scan and serialize the cache contents.
      let firstDependencyOracle = InterModuleDependencyOracle()
      try firstDependencyOracle.verifyOrCreateScannerInstance(fileSystem: localFileSystem,
                                                              swiftScanLibPath: scanLibPath)
      var firstScanDiagnostics: [ScannerDiagnosticPayload] = []
      let firstScanGraph =
        try firstDependencyOracle.getDependencies(workingDirectory: path,
                                              commandLine: scannerCommand,
                                              diagnostics: &firstScanDiagnostics)
      firstDependencyOracle.serializeScannerCache(to: cacheSavePath)

      // Run the second scan, re-using the serialized cache contents.
      let secondDependencyOracle = InterModuleDependencyOracle()
      try secondDependencyOracle.verifyOrCreateScannerInstance(fileSystem: localFileSystem,
                                                               swiftScanLibPath: scanLibPath)
      XCTAssertFalse(secondDependencyOracle.loadScannerCache(from: cacheSavePath))
      var secondScanDiagnostics: [ScannerDiagnosticPayload] = []
      let secondScanGraph =
        try secondDependencyOracle.getDependencies(workingDirectory: path,
                                                   commandLine: scannerCommand,
                                                   diagnostics: &secondScanDiagnostics)

      XCTAssertTrue(firstScanGraph.modules.count == secondScanGraph.modules.count)
    }
  }

  func testDependencyScanCommandLineEscape() throws {
#if os(Windows)
  let quoteCharacter: Character = "\""
#else
  let quoteCharacter: Character = "'"
#endif
    let swiftInputWithSpace = "/tmp/input example/test.swift"
    let swiftInputWithoutSpace = "/tmp/baz.swift"
    let clangInputWithSpace = "/tmp/input example/bar.o"
    var driver = try Driver(args: ["swiftc", "-explicit-module-build",
                                   "-module-name", "testDependencyScanning",
                                   swiftInputWithSpace, swiftInputWithoutSpace,
                                   "-Xcc", clangInputWithSpace])
    let scanJob = try driver.dependencyScanningJob()
    let scanJobCommand = try Driver.itemizedJobCommand(of: scanJob,
                                                       useResponseFiles: .disabled,
                                                       using: ArgsResolver(fileSystem: InMemoryFileSystem()))
    XCTAssertTrue(scanJobCommand.contains(String(quoteCharacter) + swiftInputWithSpace + String(quoteCharacter)))
    XCTAssertTrue(scanJobCommand.contains(String(quoteCharacter) + clangInputWithSpace + String(quoteCharacter)))
    XCTAssertTrue(scanJobCommand.contains(swiftInputWithoutSpace))
  }

  func testDependencyGraphTransitiveClosure() throws {
    let moduleDependencyGraph =
          try JSONDecoder().decode(
            InterModuleDependencyGraph.self,
            from: ModuleDependenciesInputs.simpleDependencyGraphInputWithSwiftOverlayDep.data(using: .utf8)!)
    let reachabilityMap = try moduleDependencyGraph.computeTransitiveClosure()
    let mainModuleDependencies = try XCTUnwrap(reachabilityMap[.swift("simpleTestModule")])
    let aModuleDependencies = try XCTUnwrap(reachabilityMap[.swift("A")])
    XCTAssertTrue(mainModuleDependencies.contains(.swift("B")))
    XCTAssertTrue(aModuleDependencies.contains(.swift("B")))
  }

  func testExplicitSwiftModuleMap() throws {
    let jsonExample : String = """
    [
      {
        "moduleName": "A",
        "modulePath": "A.swiftmodule",
        "docPath": "A.swiftdoc",
        "sourceInfoPath": "A.swiftsourceinfo",
        "isFramework": true
      },
      {
        "moduleName": "B",
        "modulePath": "B.swiftmodule",
        "docPath": "B.swiftdoc",
        "sourceInfoPath": "B.swiftsourceinfo",
        "isFramework": false
      }
    ]
    """
    let moduleMap = try JSONDecoder().decode(Array<SwiftModuleArtifactInfo>.self,
                                             from: jsonExample.data(using: .utf8)!)
    XCTAssertEqual(moduleMap.count, 2)
    XCTAssertEqual(moduleMap[0].moduleName, "A")
    XCTAssertEqual(moduleMap[0].modulePath.path.description, "A.swiftmodule")
    XCTAssertEqual(moduleMap[0].docPath!.path.description, "A.swiftdoc")
    XCTAssertEqual(moduleMap[0].sourceInfoPath!.path.description, "A.swiftsourceinfo")
    XCTAssertEqual(moduleMap[0].isFramework, true)
    XCTAssertEqual(moduleMap[1].moduleName, "B")
    XCTAssertEqual(moduleMap[1].modulePath.path.description, "B.swiftmodule")
    XCTAssertEqual(moduleMap[1].docPath!.path.description, "B.swiftdoc")
    XCTAssertEqual(moduleMap[1].sourceInfoPath!.path.description, "B.swiftsourceinfo")
    XCTAssertEqual(moduleMap[1].isFramework, false)
  }

  func testTraceDependency() throws {
    try withTemporaryDirectory { path in
      try localFileSystem.changeCurrentWorkingDirectory(to: path)
      let moduleCachePath = path.appending(component: "ModuleCache")
      try localFileSystem.createDirectory(moduleCachePath)
      let main = path.appending(component: "testTraceDependency.swift")
      try localFileSystem.writeFileContents(main, bytes: 
        """
        import C;\
        import E;\
        import G;
        """
      )

      let cHeadersPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "CHeaders")
      let swiftModuleInterfacesPath: AbsolutePath =
          try testInputsPath.appending(component: "ExplicitModuleBuilds")
                            .appending(component: "Swift")
      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      var driver = try Driver(args: ["swiftc",
                                     "-I", cHeadersPath.nativePathString(escaped: true),
                                     "-I", swiftModuleInterfacesPath.nativePathString(escaped: true),
                                     "-explicit-module-build", "-v",
                                     "-module-cache-path", moduleCachePath.nativePathString(escaped: true),
                                     "-working-directory", path.nativePathString(escaped: true),
                                     "-explain-module-dependency", "A",
                                     main.nativePathString(escaped: true)] + sdkArgumentsForTesting,
                              env: ProcessEnv.vars)
      let jobs = try driver.planBuild()
      try driver.run(jobs: jobs)
      XCTAssertTrue(!driver.diagnosticEngine.diagnostics.isEmpty)
      XCTAssertTrue(driver.diagnosticEngine.diagnostics.contains { $0.behavior == .remark &&
                                                                   $0.message.text == "Module 'testTraceDependency' depends on 'A'"})

      for diag in driver.diagnosticEngine.diagnostics {
        print(diag.behavior)
        print(diag.message)
      }
      XCTAssertEqual(driver.diagnosticEngine.diagnostics.filter { $0.behavior == .note}.count, 2)
      XCTAssertTrue(driver.diagnosticEngine.diagnostics.contains { $0.behavior == .note &&
                                                                   $0.message.text == "[testTraceDependency] -> [A] -> [A](ObjC)"})
      XCTAssertTrue(driver.diagnosticEngine.diagnostics.contains { $0.behavior == .note &&
                                                                   $0.message.text == "[testTraceDependency] -> [C](ObjC) -> [B](ObjC) -> [A](ObjC)"})
    }
  }

// We only care about prebuilt modules in macOS.
#if os(macOS)
  func testPrebuiltModuleGenerationJobs() throws {
    func getInputModules(_ job: Job) -> [String] {
      return job.inputs.filter {$0.type == .swiftModule}.map { input in
        return input.file.absolutePath!.parentDirectory.basenameWithoutExt
      }.sorted()
    }

    func getOutputName(_ job: Job) -> String {
      XCTAssertTrue(job.outputs.count == 1)
      return job.outputs[0].file.basename
    }

    func checkInputOutputIntegrity(_ job: Job) {
      let name = job.outputs[0].file.basenameWithoutExt
      XCTAssertTrue(job.outputs[0].file.extension == "swiftmodule")
      job.inputs.forEach { input in
        // Inputs include all the dependencies and the interface from where
        // the current module can be built.
        XCTAssertTrue(input.file.extension == "swiftmodule" ||
                      input.file.extension == "swiftinterface")
        let inputName = input.file.basenameWithoutExt
        // arm64 interface can depend on ar64e interface
        if inputName.starts(with: "arm64e-") && name.starts(with: "arm64-") {
          return
        }
        XCTAssertTrue(inputName == name)
      }
    }

    func findJob(_ jobs: [Job],_ module: String, _ basenameWithoutExt: String) -> Job? {
      return jobs.first { job in
        return job.moduleName == module &&
          job.outputs[0].file.basenameWithoutExt == basenameWithoutExt
      }
    }

    let mockSDKPath: String =
        try testInputsPath.appending(component: "mock-sdk.sdk").pathString
    let diagnosticEnging = DiagnosticsEngine()
    let collector = try SDKPrebuiltModuleInputsCollector(VirtualPath(path: mockSDKPath).absolutePath!, diagnosticEnging)
    let interfaceMap = try collector.collectSwiftInterfaceMap().inputMap

    // Check interface map always contain everything
    XCTAssertTrue(interfaceMap["Swift"]!.count == 3)
    XCTAssertTrue(interfaceMap["A"]!.count == 3)
    XCTAssertTrue(interfaceMap["E"]!.count == 3)
    XCTAssertTrue(interfaceMap["F"]!.count == 3)
    XCTAssertTrue(interfaceMap["G"]!.count == 3)
    XCTAssertTrue(interfaceMap["H"]!.count == 3)

    try withTemporaryDirectory { path in
      let main = path.appending(component: "testPrebuiltModuleGenerationJobs.swift")
      try localFileSystem.writeFileContents(main, bytes:
        """
        import A
        import E
        import F
        import G
        import H
        import Swift

        """
      )
      let moduleCachePath = "/tmp/module-cache"
      var driver = try Driver(args: ["swiftc", main.pathString,
                                     "-sdk", mockSDKPath,
                                     "-module-cache-path", moduleCachePath
                                    ])
      let (jobs, danglingJobs) = try driver.generatePrebuiltModuleGenerationJobs(with: interfaceMap,
                                                                                into: path,
                                                                                exhaustive: true)

      XCTAssertTrue(danglingJobs.count == 2)
      XCTAssertTrue(danglingJobs.allSatisfy { job in
        job.moduleName == "MissingKit"
      })
      XCTAssertTrue(jobs.count == 18)
      XCTAssertTrue(jobs.allSatisfy {$0.outputs.count == 1})
      XCTAssertTrue(jobs.allSatisfy {$0.kind == .compile})
      XCTAssertTrue(jobs.allSatisfy {$0.commandLine.contains(.flag("-compile-module-from-interface"))})
      XCTAssertTrue(jobs.allSatisfy {$0.commandLine.contains(.flag("-module-cache-path"))})
      XCTAssertTrue(jobs.allSatisfy {$0.commandLine.contains(.flag("-bad-file-descriptor-retry-count"))})
      XCTAssertTrue(try jobs.allSatisfy {$0.commandLine.contains(.path(try VirtualPath(path: moduleCachePath)))})
      let HJobs = jobs.filter { $0.moduleName == "H"}
      XCTAssertTrue(HJobs.count == 3)
      // arm64
      XCTAssertTrue(getInputModules(HJobs[0]) == ["A", "A", "E", "E", "F", "F", "G", "G", "Swift", "Swift"])
      // arm64e
      XCTAssertTrue(getInputModules(HJobs[1]) == ["A", "E", "F", "G", "Swift"])
      // x86_64
      XCTAssertTrue(getInputModules(HJobs[2]) == ["A", "E", "F", "G", "Swift"])
      XCTAssertTrue(getOutputName(HJobs[0]) != getOutputName(HJobs[1]))
      XCTAssertTrue(getOutputName(HJobs[1]) != getOutputName(HJobs[2]))
      checkInputOutputIntegrity(HJobs[0])
      checkInputOutputIntegrity(HJobs[1])
      checkInputOutputIntegrity(HJobs[2])
      let GJobs = jobs.filter { $0.moduleName == "G"}
      XCTAssertTrue(GJobs.count == 3)
      XCTAssertTrue(getInputModules(GJobs[0]) == ["E", "E", "Swift", "Swift"])
      XCTAssertTrue(getInputModules(GJobs[1]) == ["E", "Swift"])
      XCTAssertTrue(getInputModules(GJobs[2]) == ["E", "Swift"])
      XCTAssertTrue(getOutputName(GJobs[0]) != getOutputName(GJobs[1]))
      XCTAssertTrue(getOutputName(GJobs[1]) != getOutputName(GJobs[2]))
      checkInputOutputIntegrity(GJobs[0])
      checkInputOutputIntegrity(GJobs[1])
    }
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testPrebuiltModuleGenerationJobs.swift")
      try localFileSystem.writeFileContents(main, bytes: "import H\n")
      var driver = try Driver(args: ["swiftc", main.pathString,
                                     "-sdk", mockSDKPath,
                                    ])
      let (jobs, danglingJobs) = try driver.generatePrebuiltModuleGenerationJobs(with: interfaceMap,
                                                                                into: path,
                                                                                exhaustive: false)

      XCTAssertTrue(danglingJobs.isEmpty)
      XCTAssertTrue(jobs.count == 18)
      XCTAssertTrue(jobs.allSatisfy {$0.outputs.count == 1})
      XCTAssertTrue(jobs.allSatisfy {$0.kind == .compile})
      XCTAssertTrue(jobs.allSatisfy {$0.commandLine.contains(.flag("-compile-module-from-interface"))})
      let HJobs = jobs.filter { $0.moduleName == "H"}
      XCTAssertTrue(HJobs.count == 3)
      // arm64
      XCTAssertTrue(getInputModules(HJobs[0]) == ["A", "A", "E", "E", "F", "F", "G", "G", "Swift", "Swift"])
      // arm64e
      XCTAssertTrue(getInputModules(HJobs[1]) == ["A", "E", "F", "G", "Swift"])
      // x86_64
      XCTAssertTrue(getInputModules(HJobs[2]) == ["A", "E", "F", "G", "Swift"])
      XCTAssertTrue(getOutputName(HJobs[0]) != getOutputName(HJobs[1]))
      checkInputOutputIntegrity(HJobs[0])
      checkInputOutputIntegrity(HJobs[1])
      let GJobs = jobs.filter { $0.moduleName == "G"}
      XCTAssertTrue(GJobs.count == 3)
      XCTAssertTrue(getInputModules(GJobs[0]) == ["E", "E", "Swift", "Swift"])
      XCTAssertTrue(getInputModules(GJobs[1]) == ["E", "Swift"])
      XCTAssertTrue(getInputModules(GJobs[2]) == ["E", "Swift"])
      XCTAssertTrue(getOutputName(GJobs[0]) != getOutputName(GJobs[1]))
      XCTAssertTrue(getOutputName(GJobs[1]) != getOutputName(GJobs[2]))
      checkInputOutputIntegrity(GJobs[0])
      checkInputOutputIntegrity(GJobs[1])
    }
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testPrebuiltModuleGenerationJobs.swift")
      try localFileSystem.writeFileContents(main, bytes: "import Swift\n")
      var driver = try Driver(args: ["swiftc", main.pathString,
                                     "-sdk", mockSDKPath,
                                    ])
      let (jobs, danglingJobs) = try driver.generatePrebuiltModuleGenerationJobs(with: interfaceMap,
                                                                                into: path,
                                                                                exhaustive: false)

      XCTAssertTrue(danglingJobs.isEmpty)
      XCTAssert(jobs.count == 3)
      XCTAssert(jobs.allSatisfy { $0.moduleName == "Swift" })
    }
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testPrebuiltModuleGenerationJobs.swift")
      try localFileSystem.writeFileContents(main, bytes: "import F\n")
      var driver = try Driver(args: ["swiftc", main.pathString,
                                     "-sdk", mockSDKPath,
                                    ])
      let (jobs, danglingJobs) = try driver.generatePrebuiltModuleGenerationJobs(with: interfaceMap,
                                                                                into: path,
                                                                                exhaustive: false)

      XCTAssertTrue(danglingJobs.isEmpty)
      XCTAssertTrue(jobs.count == 9)
      jobs.forEach({ job in
        // Check we don't pull in other modules than A, F and Swift
        XCTAssertTrue(["A", "F", "Swift"].contains(job.moduleName))
        checkInputOutputIntegrity(job)
      })
    }
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testPrebuiltModuleGenerationJobs.swift")
      try localFileSystem.writeFileContents(main, bytes: "import H\n")
      var driver = try Driver(args: ["swiftc", main.pathString,
                                     "-sdk", mockSDKPath,
                                    ])
      let (jobs, _) = try driver.generatePrebuiltModuleGenerationJobs(with: interfaceMap,
                                                                                into: path,
                                                                                exhaustive: false)
      let F = findJob(jobs, "F", "arm64-apple-macos")!
      let H = findJob(jobs, "H", "arm64e-apple-macos")!
      // Test arm64 interface requires arm64e interfaces as inputs
      XCTAssertTrue(F.inputs.contains { input in
        input.file.basenameWithoutExt == "arm64e-apple-macos"
      })
      // Test arm64e interface doesn't require arm64 interfaces as inputs
      XCTAssertTrue(!H.inputs.contains { input in
        input.file.basenameWithoutExt == "arm64-apple-macos"
      })
    }
  }

  func testABICheckWhileBuildingPrebuiltModule() throws {
    func checkABICheckingJob(_ job: Job) throws {
      XCTAssertTrue(job.kind == .compareABIBaseline)
      XCTAssertTrue(job.inputs.count == 2)
      let (baseline, current) = (job.inputs[0], job.inputs[1])
      XCTAssertTrue(baseline.type == .jsonABIBaseline)
      XCTAssertTrue(current.type == .jsonABIBaseline)
      XCTAssertTrue(current.file != baseline.file)
      XCTAssertTrue(current.file.basename == baseline.file.basename)
    }
    let mockSDKPath: String =
        try testInputsPath.appending(component: "mock-sdk.sdk").pathString
    let baselineABIPath: String =
        try testInputsPath.appending(component: "ABIBaselines").pathString
    let collector = try SDKPrebuiltModuleInputsCollector(VirtualPath(path: mockSDKPath).absolutePath!, DiagnosticsEngine())
    let interfaceMap = try collector.collectSwiftInterfaceMap().inputMap
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testPrebuiltModuleGenerationJobs.swift")
      try localFileSystem.writeFileContents(main, bytes: "import A\n")
      let moduleCachePath = "/tmp/module-cache"
      var driver = try Driver(args: ["swiftc", main.pathString,
                                     "-sdk", mockSDKPath,
                                     "-module-cache-path", moduleCachePath
                                    ])
      let (jobs, _) = try driver.generatePrebuiltModuleGenerationJobs(with: interfaceMap,
                                                                     into: path,
                                                                     exhaustive: true,
                                                                     currentABIDir: path.appending(component: "ABI"),
                                                                     baselineABIDir: VirtualPath(path: baselineABIPath).absolutePath)
      let compileJobs = jobs.filter {$0.kind == .compile}
      XCTAssertTrue(!compileJobs.isEmpty)
      XCTAssertTrue(compileJobs.allSatisfy { $0.commandLine.contains(.flag("-compile-module-from-interface")) })
      XCTAssertTrue(compileJobs.allSatisfy { $0.commandLine.contains(.flag("-emit-abi-descriptor-path")) })
      let abiCheckJobs = jobs.filter {$0.kind == .compareABIBaseline}
      try abiCheckJobs.forEach { try checkABICheckingJob($0) }
    }
  }
  func testPrebuiltModuleInternalSDK() throws {
    let mockSDKPath = try testInputsPath.appending(component: "mock-sdk.Internal.sdk")
    let mockSDKPathStr: String = mockSDKPath.pathString
    let collector = try SDKPrebuiltModuleInputsCollector(VirtualPath(path: mockSDKPathStr).absolutePath!, DiagnosticsEngine())
    let interfaceMap = try collector.collectSwiftInterfaceMap().inputMap
    try withTemporaryDirectory { path in
      let main = path.appending(component: "testPrebuiltModuleGenerationJobs.swift")
      try localFileSystem.writeFileContents(main, bytes: "import A\n")
      let moduleCachePath = "/tmp/module-cache"
      var driver = try Driver(args: ["swiftc", main.pathString,
                                     "-sdk", mockSDKPathStr,
                                     "-module-cache-path", moduleCachePath
                                    ])
      let (jobs, _) = try driver.generatePrebuiltModuleGenerationJobs(with: interfaceMap,
                                                                     into: path,
                                                                     exhaustive: true)
      let compileJobs = jobs.filter {$0.kind == .compile}
      XCTAssertTrue(!compileJobs.isEmpty)
      XCTAssertTrue(compileJobs.allSatisfy { $0.commandLine.contains(.flag("-suppress-warnings")) })
      let PFPath = mockSDKPath.appending(component: "System").appending(component: "Library")
        .appending(component: "PrivateFrameworks")
      XCTAssertTrue(compileJobs.allSatisfy { $0.commandLine.contains(.path(VirtualPath.absolute(PFPath))) })
    }
  }
  func testCollectSwiftAdopters() throws {
    let mockSDKPath = try testInputsPath.appending(component: "mock-sdk.Internal.sdk")
    let mockSDKPathStr: String = mockSDKPath.pathString
    let collector = try SDKPrebuiltModuleInputsCollector(VirtualPath(path: mockSDKPathStr).absolutePath!, DiagnosticsEngine())
    let adopters = try collector.collectSwiftInterfaceMap().adopters
    XCTAssertTrue(!adopters.isEmpty)
    let A = adopters.first {$0.name == "A"}!
    XCTAssertFalse(A.isFramework)
    XCTAssertFalse(A.isPrivate)
    XCTAssertFalse(A.hasModule)
    XCTAssertFalse(A.hasPrivateInterface)
    XCTAssertFalse(A.hasPackageInterface)
    XCTAssertTrue(A.hasInterface)

    let B = adopters.first {$0.name == "B"}!
    XCTAssertTrue(B.isFramework)
    XCTAssertFalse(B.isPrivate)
    XCTAssertFalse(B.hasModule)
    XCTAssertTrue(B.hasPrivateInterface)
    XCTAssertFalse(B.hasPackageInterface)
  }

  func testCollectSwiftAdoptersWhetherMixed() throws {
    let mockSDKPath = try testInputsPath.appending(component: "mock-sdk.Internal.sdk")
    let mockSDKPathStr: String = mockSDKPath.pathString
    let collector = try SDKPrebuiltModuleInputsCollector(VirtualPath(path: mockSDKPathStr).absolutePath!, DiagnosticsEngine())
    let adopters = try collector.collectSwiftInterfaceMap().adopters
    XCTAssertTrue(!adopters.isEmpty)
    let B = adopters.first {$0.name == "B"}!
    XCTAssertTrue(B.isFramework)
    XCTAssertTrue(B.hasCompatibilityHeader)
    XCTAssertFalse(B.isMixed)

    let C = adopters.first {$0.name == "C"}!
    XCTAssertTrue(C.isFramework)
    XCTAssertFalse(C.hasCompatibilityHeader)
    XCTAssertTrue(C.isMixed)
  }
#endif
}
