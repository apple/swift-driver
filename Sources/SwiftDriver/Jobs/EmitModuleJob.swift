//===--------------- EmitModuleJob.swift - Swift Module Emission Job ------===//
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
extension Driver {
  /// Add options that are common to command lines that emit modules, e.g.,
  /// options for the paths of various module files.
  mutating func addCommonModuleOptions(
      commandLine: inout [Job.ArgTemplate],
      outputs: inout [TypedVirtualPath],
      isMergeModule: Bool
  ) {
    // Add supplemental outputs.
    func addSupplementalOutput(path: VirtualPath.Handle?, flag: String, type: FileType) {
      guard let path = path else { return }

      commandLine.appendFlag(flag)
      commandLine.appendPath(VirtualPath.lookup(path))
      outputs.append(.init(file: path, type: type))
    }

    addSupplementalOutput(path: moduleDocOutputPath, flag: "-emit-module-doc-path", type: .swiftDocumentation)
    addSupplementalOutput(path: moduleSourceInfoPath, flag: "-emit-module-source-info-path", type: .swiftSourceInfoFile)
    addSupplementalOutput(path: swiftInterfacePath, flag: "-emit-module-interface-path", type: .swiftInterface)
    addSupplementalOutput(path: swiftPrivateInterfacePath, flag: "-emit-private-module-interface-path", type: .privateSwiftInterface)
    addSupplementalOutput(path: objcGeneratedHeaderPath, flag: "-emit-objc-header-path", type: .objcHeader)
    addSupplementalOutput(path: tbdPath, flag: "-emit-tbd-path", type: .tbd)

    if isMergeModule || shouldCreateEmitModuleJob {
      return
    }
    // Add outputs that can't be merged
    addSupplementalOutput(path: serializedDiagnosticsFilePath, flag: "-serialize-diagnostics-path", type: .diagnostics)
    if let dependenciesFilePath = dependenciesFilePath {
      var path = dependenciesFilePath
      // FIXME: Hack to workaround the fact that SwiftPM/Xcode don't pass this path right now.
      if parsedOptions.getLastArgument(.emitDependenciesPath) == nil {
        path = VirtualPath.lookup(moduleOutputInfo.output!.outputPath).replacingExtension(with: .dependencies).intern()
      }
      addSupplementalOutput(path: path, flag: "-emit-dependencies-path", type: .dependencies)
    }
  }

  /// Form a job that emits a single module
  @_spi(Testing) public mutating func emitModuleJob() throws -> Job {
    let moduleOutputPath = moduleOutputInfo.output!.outputPath
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }
    var inputs: [TypedVirtualPath] = []
    var outputs: [TypedVirtualPath] = [
      TypedVirtualPath(file: moduleOutputPath, type: .swiftModule)
    ]

    commandLine.appendFlags("-frontend", "-emit-module", "-experimental-skip-non-inlinable-function-bodies-without-types")

    // Add the inputs.
    for input in self.inputFiles where input.type.isPartOfSwiftCompilation {
      commandLine.append(.path(input.file))
      inputs.append(input)
    }

    if let pchPath = bridgingPrecompiledHeader {
      inputs.append(TypedVirtualPath(file: pchPath, type: .pch))
    }

    try addCommonFrontendOptions(commandLine: &commandLine, inputs: &inputs)
    // FIXME: Add MSVC runtime library flags

    addCommonModuleOptions(commandLine: &commandLine, outputs: &outputs, isMergeModule: false)

    if parsedOptions.hasArgument(.parseAsLibrary, .emitLibrary) {
      commandLine.appendFlag(.parseAsLibrary)
    }

    commandLine.appendFlag(.o)
    commandLine.appendPath(VirtualPath.lookup(moduleOutputPath))

    return Job(
      moduleName: moduleOutputInfo.name,
      kind: .emitModule,
      tool: try toolchain.getToolPathHandle(.swiftCompiler),
      commandLine: commandLine,
      inputs: inputs,
      primaryInputs: [],
      outputs: outputs
    )
  }

  /// Returns true if the emit module job should be created.
  var shouldCreateEmitModuleJob: Bool {
    mutating get {
      return moduleOutputInfo.output != nil
        && (forceEmitModuleBeforeCompile
            || shouldEmitModuleSeparately())
    }
  }

  /// Returns true if the -emit-module-separately is active.
  mutating func shouldEmitModuleSeparately() -> Bool {
    return parsedOptions.hasArgument(.emitModuleSeparately)
           && !parsedOptions.hasFlag(positive: .wholeModuleOptimization,
                                     negative: .noWholeModuleOptimization,
                                     default: false)
  }
}
