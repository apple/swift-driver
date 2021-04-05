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
import TSCBasic
import TSCUtility
import SwiftOptions

extension DarwinToolchain {
  internal func findXcodeClangLibPath(_ additionalPath: String) throws -> AbsolutePath? {
    let path = try getToolPath(.swiftCompiler)
      .parentDirectory // 'swift'
      .parentDirectory // 'bin'
      .appending(components: "lib", additionalPath)

    if fileSystem.exists(path) { return path }

    // If we don't have a 'lib/arc/' directory, find the "arclite" library
    // relative to the Clang in the active Xcode.
    if let clangPath = try? getToolPath(.clang) {
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

  internal func addLTOLibArgs(to commandLine: inout [Job.ArgTemplate]) throws {
    if let path = try findXcodeClangLibPath("libLTO.dylib") {
      commandLine.appendFlag("-lto_library")
      commandLine.appendPath(path)
    }
  }

  func addLinkRuntimeLibraryRPath(
    to commandLine: inout [Job.ArgTemplate],
    parsedOptions: inout ParsedOptions,
    targetInfo: FrontendTargetInfo,
    darwinLibName: String
  ) throws {
    // Adding the rpaths might negatively interact when other rpaths are involved,
    // so we should make sure we add the rpaths last, after all user-specified
    // rpaths. This is currently true from this place, but we need to be
    // careful if this function is ever called before user's rpaths are emitted.
    assert(darwinLibName.hasSuffix(".dylib"), "must be a dynamic library")

    // Add @executable_path to rpath to support having the dylib copied with
    // the executable.
    commandLine.appendFlag("-rpath")
    commandLine.appendFlag("@executable_path")

    // Add the path to the resource dir to rpath to support using the dylib
    // from the default location without copying.


    let clangPath = try clangLibraryPath(
      for: targetInfo,
      parsedOptions: &parsedOptions)
    commandLine.appendFlag("-rpath")
    commandLine.appendPath(clangPath)
  }

  func addLinkSanitizerLibArgsForDarwin(
    to commandLine: inout [Job.ArgTemplate],
    parsedOptions: inout ParsedOptions,
    targetInfo: FrontendTargetInfo,
    sanitizer: Sanitizer,
    isShared: Bool
  ) throws {
    // Sanitizer runtime libraries requires C++.
    commandLine.appendFlag("-lc++")
    // Add explicit dependency on -lc++abi, as -lc++ doesn't re-export
    // all RTTI-related symbols that are used.
    commandLine.appendFlag("-lc++abi")

    let sanitizerName = try runtimeLibraryName(
      for: sanitizer,
      targetTriple: targetInfo.target.triple,
      isShared: isShared
    )
    try addLinkRuntimeLibrary(
      named: sanitizerName,
      to: &commandLine,
      for: targetInfo,
      parsedOptions: &parsedOptions
    )

    if isShared {
      try addLinkRuntimeLibraryRPath(
        to: &commandLine,
        parsedOptions: &parsedOptions,
        targetInfo: targetInfo,
        darwinLibName: sanitizerName
      )
    }
  }

  private func addProfileGenerationArgs(
    to commandLine: inout [Job.ArgTemplate],
    parsedOptions: inout ParsedOptions,
    targetInfo: FrontendTargetInfo
  ) throws {
    guard parsedOptions.hasArgument(.profileGenerate) else { return }
    let clangPath = try clangLibraryPath(for: targetInfo,
                                         parsedOptions: &parsedOptions)

    for runtime in targetInfo.target.triple.darwinPlatform!.profileLibraryNameSuffixes {
      let clangRTPath = clangPath
        .appending(component: "libclang_rt.profile_\(runtime).a")
      commandLine.appendPath(clangRTPath)
    }
  }

  private func addPlatformVersionArg(to commandLine: inout [Job.ArgTemplate],
                                     for triple: Triple, sdkPath: VirtualPath.Handle?) {
    assert(triple.isDarwin)
    let platformName = triple.darwinPlatform!.linkerPlatformName
    let platformVersion = triple.darwinLinkerPlatformVersion
    let sdkVersion: Version
    if let sdkPath = sdkPath,
       let sdkInfo = getTargetSDKInfo(sdkPath: sdkPath) {
      sdkVersion = sdkInfo.sdkVersion(for: triple)
    } else {
      sdkVersion = Version(0, 0, 0)
    }

    commandLine.append(.flag("-platform_version"))
    commandLine.append(.flag(platformName))
    commandLine.append(.flag(platformVersion.description))
    commandLine.append(.flag(sdkVersion.description))
  }

  private func addDeploymentTargetArgs(
    to commandLine: inout [Job.ArgTemplate],
    targetTriple: Triple,
    targetVariantTriple: Triple?,
    sdkPath: VirtualPath.Handle?
  ) {
    addPlatformVersionArg(to: &commandLine, for: targetTriple, sdkPath: sdkPath)
    if let variantTriple = targetVariantTriple {
      assert(targetTriple.isValidForZipperingWithTriple(variantTriple))
      addPlatformVersionArg(to: &commandLine, for: variantTriple,
                            sdkPath: sdkPath)
    }
  }

  private func addArgsToLinkARCLite(
    to commandLine: inout [Job.ArgTemplate],
    parsedOptions: inout ParsedOptions,
    targetTriple: Triple
  ) throws {
    guard parsedOptions.hasFlag(
      positive: .linkObjcRuntime,
      negative: .noLinkObjcRuntime,
      default: !targetTriple.supports(.compatibleObjCRuntime)
    ) else {
      return
    }

    guard let arcLiteLibPath = try findARCLiteLibPath(),
      let platformName = targetTriple.platformName() else {
        return
    }
    let fullLibPath = arcLiteLibPath
      .appending(components: "libarclite_\(platformName).a")

    commandLine.appendFlag("-force_load")
    commandLine.appendPath(fullLibPath)

    // Arclite depends on CoreFoundation.
    commandLine.appendFlag(.framework)
    commandLine.appendFlag("CoreFoundation")
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
  ) throws -> AbsolutePath {
    // Set up for linking.
    let linkerTool: Tool
    switch linkerOutputType {
    case .dynamicLibrary:
      // Same as an executable, but with the -dylib flag
      linkerTool = .dynamicLinker
      commandLine.appendFlag("-dylib")
      addLinkInputs(shouldUseInputFileList: shouldUseInputFileList,
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
      addLinkInputs(shouldUseInputFileList: shouldUseInputFileList,
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
      addLinkInputs(shouldUseInputFileList: shouldUseInputFileList,
                    commandLine: &commandLine,
                    inputs: inputs,
                    linkerOutputType: linkerOutputType)
    }

    // Add the output
    commandLine.appendFlag("-o")
    commandLine.appendPath(outputFile)

    return try getToolPath(linkerTool)
  }

  private func addLinkInputs(shouldUseInputFileList: Bool,
                             commandLine: inout [Job.ArgTemplate],
                             inputs: [TypedVirtualPath],
                             linkerOutputType: LinkOutputType) {
    // inputs LinkFileList
    if shouldUseInputFileList {
      commandLine.appendFlag(.filelist)
      let path = RelativePath(createTemporaryFileName(prefix: "inputs", suffix: "LinkFileList"))
      var inputPaths = [VirtualPath.Handle]()
      var inputModules = [VirtualPath]()
      for input in inputs {
        if input.type == .swiftModule && linkerOutputType != .staticLibrary {
          inputPaths.append(input.fileHandle)
          inputModules.append(input.file)
        } else if input.type == .object {
          inputPaths.append(input.fileHandle)
        } else if input.type == .llvmBitcode {
          inputPaths.append(input.fileHandle)
        }
      }
      commandLine.appendPath(.fileList(path, .list(inputPaths)))
      if linkerOutputType != .staticLibrary {
        for module in inputModules {
          commandLine.append(.flag("-add_ast_path"))
          commandLine.append(.path(module))
        }
      }

      // FIXME: Primary inputs need to check -index-file-path
    } else {
      // Add inputs.
      commandLine.append(contentsOf: inputs.flatMap {
        (path: TypedVirtualPath) -> [Job.ArgTemplate] in
        if path.type == .swiftModule && linkerOutputType != .staticLibrary {
          return [.flag("-add_ast_path"), .path(path.file)]
        } else if path.type == .object {
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
    // FIXME: If we used Clang as a linker instead of going straight to ld,
    // we wouldn't have to replicate a bunch of Clang's logic here.

    // Always link the regular compiler_rt if it's present. Note that the
    // regular libclang_rt.a uses a fat binary for device and simulator; this is
    // not true for all compiler_rt build products.
    //
    // Note: Normally we'd just add this unconditionally, but it's valid to build
    // Swift and use it as a linker without building compiler_rt.
    let targetTriple = targetInfo.target.triple
    let darwinPlatformSuffix =
      targetTriple.darwinPlatform!.with(.device)!.libraryNameSuffix
    let compilerRTPath =
      try clangLibraryPath(
        for: targetInfo,
        parsedOptions: &parsedOptions)
      .appending(component: "libclang_rt.\(darwinPlatformSuffix).a")
    if try fileSystem.exists(compilerRTPath) {
      commandLine.append(.path(compilerRTPath))
    }

    try addArgsToLinkARCLite(
      to: &commandLine,
      parsedOptions: &parsedOptions,
      targetTriple: targetTriple
    )

    if lto != nil {
      try addLTOLibArgs(to: &commandLine)
    }

    let fSystemArgs = parsedOptions.arguments(for: .F, .Fsystem)
    for opt in fSystemArgs {
      commandLine.appendFlag(.F)
      commandLine.appendPath(try VirtualPath(path: opt.argument.asSingle))
    }

    if parsedOptions.contains(.enableAppExtension) {
      commandLine.appendFlag("-application_extension")
    }

    // Linking sanitizers will add rpaths, which might negatively interact when
    // other rpaths are involved, so we should make sure we add the rpaths after
    // all user-specified rpaths.
    for sanitizer in sanitizers {
      if sanitizer == .fuzzer {
        guard linkerOutputType == .executable else { continue }
      }
      try addLinkSanitizerLibArgsForDarwin(
        to: &commandLine,
        parsedOptions: &parsedOptions,
        targetInfo: targetInfo,
        sanitizer: sanitizer,
        isShared: sanitizer != .fuzzer
      )
    }

    if parsedOptions.contains(.embedBitcode) ||
        parsedOptions.contains(.embedBitcodeMarker) {
      commandLine.appendFlag("-bitcode_bundle")
    }

    // Add the SDK path
    if let sdkPath = targetInfo.sdkPath?.path {
      commandLine.appendFlag("-syslibroot")
      commandLine.appendPath(VirtualPath.lookup(sdkPath))
    }

    commandLine.appendFlags(
      "-lobjc",
      "-lSystem"
    )

    commandLine.appendFlag("-arch")
    commandLine.appendFlag(targetTriple.archName)

    // On Darwin, we only support libc++.
    if parsedOptions.contains(.enableExperimentalCxxInterop) {
      commandLine.appendFlag("-lc++")
    }

    try addArgsToLinkStdlib(
      to: &commandLine,
      parsedOptions: &parsedOptions,
      targetInfo: targetInfo,
      linkerOutputType: linkerOutputType,
      fileSystem: fileSystem
    )

    try addProfileGenerationArgs(
      to: &commandLine,
      parsedOptions: &parsedOptions,
      targetInfo: targetInfo
    )

    let targetVariantTriple = targetInfo.targetVariant?.triple
    addDeploymentTargetArgs(
      to: &commandLine,
      targetTriple: targetTriple,
      targetVariantTriple: targetVariantTriple,
      sdkPath: targetInfo.sdkPath?.path
    )

    commandLine.appendFlag("-no_objc_category_merging")

    // These custom arguments should be right before the object file at the
    // end.
    try commandLine.append(
      contentsOf: parsedOptions.arguments(in: .linkerOption)
    )
    try commandLine.appendAllArguments(.Xlinker, from: &parsedOptions)
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
    }
  }
}
