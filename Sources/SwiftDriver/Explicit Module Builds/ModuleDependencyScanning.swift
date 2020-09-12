//===--------------- ModuleDependencyScanning.swift -----------------------===//
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
import Foundation
import TSCBasic
import SwiftOptions

extension Driver {
  /// Precompute the dependencies for a given Swift compilation, producing a
  /// dependency graph including all Swift and C module files and
  /// source files.
  mutating func dependencyScanningJob() throws -> Job {
    var inputs: [TypedVirtualPath] = []

    // Aggregate the fast dependency scanner arguments
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }
    commandLine.appendFlag("-frontend")
    commandLine.appendFlag("-scan-dependencies")
    try addCommonFrontendOptions(commandLine: &commandLine, inputs: &inputs,
                                 bridgingHeaderHandling: .precompiled,
                                 moduleDependencyGraphUse: .dependencyScan)
    // FIXME: MSVC runtime flags

    // Pass in external dependencies to be treated as placeholder dependencies by the scanner
    if let externalDependencyArtifactMap = externalDependencyArtifactMap {
      let dependencyPlaceholderMapFile =
        try serializeExternalDependencyArtifacts(externalDependencyArtifactMap:
                                                  externalDependencyArtifactMap)
      commandLine.appendFlag("-placeholder-dependency-module-map-file")
      commandLine.appendPath(dependencyPlaceholderMapFile)
    }

    // Pass on the input files
    commandLine.append(contentsOf: inputFiles.map { .path($0.file)})

    // Construct the scanning job.
    return Job(moduleName: moduleOutputInfo.name,
               kind: .scanDependencies,
               tool: VirtualPath.absolute(try toolchain.getToolPath(.swiftCompiler)),
               commandLine: commandLine,
               displayInputs: inputs,
               inputs: inputs,
               outputs: [TypedVirtualPath(file: .standardOutput, type: .jsonDependencies)],
               supportsResponseFiles: true)
  }

  /// Serialize a map of placeholder (external) dependencies for the dependency scanner.
  func serializeExternalDependencyArtifacts(externalDependencyArtifactMap: ExternalDependencyArtifactMap)
  throws -> VirtualPath {
    var placeholderArtifacts: [SwiftModuleArtifactInfo] = []
    for (moduleId, dependencyInfo) in externalDependencyArtifactMap {
      placeholderArtifacts.append(
          SwiftModuleArtifactInfo(name: moduleId.moduleName,
                                  modulePath: dependencyInfo.0.description))
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted]
    let contents = try encoder.encode(placeholderArtifacts)
    return .temporaryWithKnownContents(.init("\(moduleOutputInfo.name)-placeholder-modules.json"), contents)
  }

  mutating func performBatchDependencyScan(moduleInfos: [BatchScanModuleInfo])
  throws -> [ModuleDependencyId: [InterModuleDependencyGraph]] {
    let batchScanningJob = try batchDependencyScanningJob(for: moduleInfos)
    let forceResponseFiles = parsedOptions.hasArgument(.driverForceResponseFiles)
    let batchScanResult =
      try self.executor.execute(job: batchScanningJob,
                                forceResponseFiles: forceResponseFiles,
                                recordedInputModificationDates: recordedInputModificationDates)
    let success = batchScanResult.exitStatus == .terminated(code: EXIT_SUCCESS)
    guard success else {
      throw JobExecutionError.jobFailedWithNonzeroExitCode(
        SwiftDriverExecutor.computeReturnCode(exitStatus: batchScanResult.exitStatus),
        try batchScanResult.utf8stderrOutput())
    }

    // Decode the resulting dependency graphs and build a dictionary from a moduleId to
    // a set of dependency graphs that were built for it
    let moduleVersionedGraphMap =
      try moduleInfos.reduce(into: [ModuleDependencyId: [InterModuleDependencyGraph]]()) {
      let moduleId: ModuleDependencyId
      let dependencyGraphPath: VirtualPath
      switch $1 {
        case .swift(let swiftModuleBatchScanInfo):
          moduleId = .swift(swiftModuleBatchScanInfo.swiftModuleName)
          dependencyGraphPath = try VirtualPath(path: swiftModuleBatchScanInfo.output)
        case .clang(let clangModuleBatchScanInfo):
          moduleId = .clang(clangModuleBatchScanInfo.clangModuleName)
          dependencyGraphPath = try VirtualPath(path: clangModuleBatchScanInfo.output)
      }
      let contents = try fileSystem.readFileContents(dependencyGraphPath)
      let decodedGraph = try JSONDecoder().decode(InterModuleDependencyGraph.self,
                                            from: Data(contents.contents))
      if $0[moduleId] != nil {
        $0[moduleId]!.append(decodedGraph)
      } else {
        $0[moduleId] = [decodedGraph]
      }
    }
    return moduleVersionedGraphMap
  }

  /// Precompute the dependencies for a given collection of modules using swift frontend's batch scanning mode
  mutating func batchDependencyScanningJob(for moduleInfos: [BatchScanModuleInfo]) throws -> Job {
    var inputs: [TypedVirtualPath] = []

    // Aggregate the fast dependency scanner arguments
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }
    commandLine.appendFlag("-frontend")
    // The dependency scanner automatically operates in batch mode if -batch-scan-input-file
    // is present.
    commandLine.appendFlag("-scan-dependencies")
    try addCommonFrontendOptions(commandLine: &commandLine, inputs: &inputs,
                                 bridgingHeaderHandling: .precompiled,
                                 moduleDependencyGraphUse: .dependencyScan)

    let batchScanInputFilePath = try serializeBatchScanningModuleArtifacts(moduleInfos: moduleInfos)
    commandLine.appendFlag("-batch-scan-input-file")
    commandLine.appendPath(batchScanInputFilePath)

    // This action does not require any input files, but all frontend actions require
    // at least one input so pick any input of the current compilation.
    let inputFile = inputFiles.first { $0.type == .swift }
    commandLine.appendPath(inputFile!.file)
    inputs.append(inputFile!)

    // This job's outputs are defined as a set of dependency graph json files
    let outputs: [TypedVirtualPath] = try moduleInfos.map {
      switch $0 {
        case .swift(let swiftModuleBatchScanInfo):
          return TypedVirtualPath(file: try VirtualPath(path: swiftModuleBatchScanInfo.output),
                                  type: .jsonDependencies)
        case .clang(let clangModuleBatchScanInfo):
          return TypedVirtualPath(file: try VirtualPath(path: clangModuleBatchScanInfo.output),
                                  type: .jsonDependencies)
      }
    }

    // Construct the scanning job.
    return Job(moduleName: moduleOutputInfo.name,
               kind: .scanDependencies,
               tool: VirtualPath.absolute(try toolchain.getToolPath(.swiftCompiler)),
               commandLine: commandLine,
               displayInputs: inputs,
               inputs: inputs,
               outputs: outputs,
               supportsResponseFiles: true)
  }

  /// Serialize a collection of modules into an input format expected by the batch module dependency scanner.
  func serializeBatchScanningModuleArtifacts(moduleInfos: [BatchScanModuleInfo])
  throws -> VirtualPath {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted]
    let contents = try encoder.encode(moduleInfos)
    return .temporaryWithKnownContents(.init("\(moduleOutputInfo.name)-batch-module-scan.json"), contents)
  }
}
