//===--------------- DarwinToolchain+LinkerSupport.swift ------------------===//
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

import SwiftOptions

import struct TSCBasic.AbsolutePath
import struct TSCBasic.RelativePath

extension DarwinToolchain {
  internal func findXcodeClangPath() throws -> AbsolutePath? {
    let result = try executor.checkNonZeroExit(
      args: "xcrun", "-toolchain", "default", "-f", "clang",
      environment: env
    ).trimmingCharacters(in: .whitespacesAndNewlines)

    return result.isEmpty ? nil : try AbsolutePath(validating: result)
  }

  internal func findXcodeClangLibPath(_ additionalPath: String) throws -> AbsolutePath? {
    let path = try getToolPath(.swiftCompiler)
      .parentDirectory // 'swift'
      .parentDirectory // 'bin'
      .appending(components: "lib", additionalPath)

    if fileSystem.exists(path) { return path }

    // If we don't have a 'lib/arc/' directory, find the "arclite" library
    // relative to the Clang in the active Xcode.
    if let clangPath = try? findXcodeClangPath() {
      return clangPath
        .parentDirectory // 'clang'
        .parentDirectory // 'bin'
        .appending(components: "lib", additionalPath)
    }
    return nil
  }

  internal func findARCLiteLibPath() throws -> AbsolutePath? {
    return try findXcodeClangLibPath("arc")
  }

  /// Adds the arguments necessary to link the files from the given set of
  /// options for a Darwin platform.
  public func addPlatformSpecificLinkerArgs(
    to commandLine: inout [Job.ArgTemplate],
    parsedOptions: inout ParsedOptions,
    linkerOutputType: LinkOutputType,
    inputs: [TypedVirtualPath],
    outputFile: VirtualPath,
    shouldUseInputFileList: Bool,
    lto: LTOKind?,
    sanitizers: Set<Sanitizer>,
    targetInfo: FrontendTargetInfo
  ) throws -> ResolvedTool {
    // Set up for linking.
    let linkerTool: Tool
    switch linkerOutputType {
    case .dynamicLibrary:
      // Same as an executable, but with the -dylib flag
      linkerTool = .dynamicLinker
      commandLine.appendFlag("-dynamiclib")
      try addLinkInputs(shouldUseInputFileList: shouldUseInputFileList,
                        commandLine: &commandLine,
                        inputs: inputs,
                        linkerOutputType: linkerOutputType)
      try addDynamicLinkerFlags(targetInfo: targetInfo,
                                parsedOptions: &parsedOptions,
                                commandLine: &commandLine,
                                sanitizers: sanitizers,
                                linkerOutputType: linkerOutputType,
                                lto: lto)

    case .executable:
      linkerTool = .dynamicLinker
      try addLinkInputs(shouldUseInputFileList: shouldUseInputFileList,
                        commandLine: &commandLine,
                        inputs: inputs,
                        linkerOutputType: linkerOutputType)
      try addDynamicLinkerFlags(targetInfo: targetInfo,
                                parsedOptions: &parsedOptions,
                                commandLine: &commandLine,
                                sanitizers: sanitizers,
                                linkerOutputType: linkerOutputType,
                                lto: lto)

    case .staticLibrary:
      linkerTool = .staticLinker(lto)
      commandLine.appendFlag(.static)
      try addLinkInputs(shouldUseInputFileList: shouldUseInputFileList,
                        commandLine: &commandLine,
                        inputs: inputs,
                        linkerOutputType: linkerOutputType)
    }

    // Add the output
    commandLine.appendFlag("-o")
    commandLine.appendPath(outputFile)

    return try resolvedTool(linkerTool)
  }

  private func addLinkInputs(shouldUseInputFileList: Bool,
                             commandLine: inout [Job.ArgTemplate],
                             inputs: [TypedVirtualPath],
                             linkerOutputType: LinkOutputType) throws {
    // inputs LinkFileList
    if shouldUseInputFileList {
      commandLine.appendFlag(.filelist)
      var inputPaths = [VirtualPath]()
      var inputModules = [VirtualPath]()
      for input in inputs {
        if input.type == .swiftModule && linkerOutputType != .staticLibrary {
          inputPaths.append(input.file)
          inputModules.append(input.file)
        } else if input.type == .object {
          inputPaths.append(input.file)
        } else if input.type == .tbd {
          inputPaths.append(input.file)
        } else if input.type == .llvmBitcode {
          inputPaths.append(input.file)
        }
      }
      let fileList = try VirtualPath.createUniqueFilelist(RelativePath(validating: "inputs.LinkFileList"),
                                                          .list(inputPaths))
      commandLine.appendPath(fileList)
      if linkerOutputType != .staticLibrary {
        for module in inputModules {
          commandLine.append(.joinedOptionAndPath("-Wl,-add_ast_path,", module))
        }
      }

      // FIXME: Primary inputs need to check -index-file-path
    } else {
      // Add inputs.
      commandLine.append(contentsOf: inputs.flatMap {
        (path: TypedVirtualPath) -> [Job.ArgTemplate] in
        if path.type == .swiftModule && linkerOutputType != .staticLibrary {
          return [.joinedOptionAndPath("-Wl,-add_ast_path,", path.file)]
        } else if path.type == .object {
          return [.path(path.file)]
        } else if path.type == .tbd {
          return [.path(path.file)]
        } else if path.type == .llvmBitcode {
          return [.path(path.file)]
        } else {
          return []
        }
      })
    }
  }

  private func addDynamicLinkerFlags(targetInfo: FrontendTargetInfo,
                                     parsedOptions: inout ParsedOptions,
                                     commandLine: inout [Job.ArgTemplate],
                                     sanitizers: Set<Sanitizer>,
                                     linkerOutputType: LinkOutputType,
                                     lto: LTOKind?) throws {
    if let lto = lto {
      switch lto {
      case .llvmFull:
        commandLine.appendFlag("-flto=full")
      case .llvmThin:
        commandLine.appendFlag("-flto=thin")
      }

      if let arg = parsedOptions.getLastArgument(.ltoLibrary)?.asSingle {
        commandLine.append(.joinedOptionAndPath("-Wl,-lto_library,", try VirtualPath(path: arg)))
      }
    }

    if let arg = parsedOptions.getLastArgument(.useLd)?.asSingle {
      commandLine.appendFlag("-fuse-ld=\(arg)")
    }

    if let arg = parsedOptions.getLastArgument(.ldPath)?.asSingle {
      commandLine.append(.joinedOptionAndPath("--ld-path=", try VirtualPath(path: arg)))
    }

    let fSystemArgs = parsedOptions.arguments(for: .F, .Fsystem)
    for opt in fSystemArgs {
      commandLine.appendFlag(.F)
      commandLine.appendPath(try VirtualPath(path: opt.argument.asSingle))
    }

    if parsedOptions.contains(.enableAppExtension) {
      commandLine.appendFlag("-fapplication-extension")
    }

    // Pass down an optimization level
    if let optArg = mapOptimizationLevelToClangArg(from: &parsedOptions) {
      commandLine.appendFlag(optArg)
    }

    // Linking sanitizers will add rpaths, which might negatively interact when
    // other rpaths are involved, so we should make sure we add the rpaths after
    // all user-specified rpaths.
    if linkerOutputType != .staticLibrary && !sanitizers.isEmpty {
      let sanitizerNames = sanitizers
        .map { $0.rawValue }
        .sorted() // Sort so we get a stable, testable order
        .joined(separator: ",")
      commandLine.appendFlag("-fsanitize=\(sanitizerNames)")

      if parsedOptions.contains(.sanitizeStableAbiEQ) {
        commandLine.appendFlag("-fsanitize-stable-abi")
      }
    }

    if parsedOptions.contains(.embedBitcode) {
      commandLine.appendFlag("-fembed-bitcode")
    } else if parsedOptions.contains(.embedBitcodeMarker) {
      commandLine.appendFlag("-fembed-bitcode=marker")
    }

    // Add the SDK path
    if let sdkPath = targetInfo.sdkPath?.path {
      commandLine.appendFlag("--sysroot")
      commandLine.appendPath(VirtualPath.lookup(sdkPath))
    }

    // -link-objc-runtime also implies -fobjc-link-runtime
    if parsedOptions.hasFlag(positive: .linkObjcRuntime,
                             negative: .noLinkObjcRuntime,
                             default: false) {
      commandLine.appendFlag("-fobjc-link-runtime")
    }

    let targetTriple = targetInfo.target.triple
    commandLine.appendFlag("--target=\(targetTriple.triple)")
    if let variantTriple = targetInfo.targetVariant?.triple {
      assert(targetTriple.isValidForZipperingWithTriple(variantTriple))
      commandLine.appendFlag("-darwin-target-variant=\(variantTriple.triple)")
    }

    // On Darwin, we only support libc++.
    var cxxCompatEnabled = parsedOptions.hasArgument(.enableExperimentalCxxInterop)
    if let cxxInteropMode = parsedOptions.getLastArgument(.cxxInteroperabilityMode) {
      if cxxInteropMode.asSingle == "swift-5.9" {
        cxxCompatEnabled = true
      }
    }
    if cxxCompatEnabled {
      commandLine.appendFlag("-lc++")
    }

    try addArgsToLinkStdlib(
      to: &commandLine,
      parsedOptions: &parsedOptions,
      targetInfo: targetInfo,
      linkerOutputType: linkerOutputType,
      fileSystem: fileSystem
    )

    if parsedOptions.hasArgument(.profileGenerate) {
      commandLine.appendFlag("-fprofile-generate")
    }

    // These custom arguments should be right before the object file at the
    // end.
    try commandLine.appendAllExcept(
      includeList: [.linkerOption],
      excludeList: [.l],
      from: &parsedOptions
    )
    addLinkedLibArgs(to: &commandLine, parsedOptions: &parsedOptions)
    try addExtraClangLinkerArgs(to: &commandLine, parsedOptions: &parsedOptions)
  }
}

private extension DarwinPlatform {
  var profileLibraryNameSuffixes: [String] {
    switch self {
    case .macOS, .iOS(.catalyst):
      return ["osx"]
    case .iOS(.device):
      return ["ios"]
    case .iOS(.simulator):
      return ["iossim", "ios"]
    case .tvOS(.device):
      return ["tvos"]
    case .tvOS(.simulator):
      return ["tvossim", "tvos"]
    case .watchOS(.device):
      return ["watchos"]
    case .watchOS(.simulator):
      return ["watchossim", "watchos"]
    case .visionOS(.device):
      return ["xros"]
    case .visionOS(.simulator):
      return ["xrossim", "xros"]
    }
  }
}
