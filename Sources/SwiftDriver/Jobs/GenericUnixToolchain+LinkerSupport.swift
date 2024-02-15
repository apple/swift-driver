//===--------------- GenericUnixToolchain+LinkerSupport.swift -------------===//
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

import func TSCBasic.lookupExecutablePath
import struct TSCBasic.AbsolutePath

extension GenericUnixToolchain {
  private func majorArchitectureName(for triple: Triple) -> String {
    // The concept of a "major" arch name only applies to Linux triples
    guard triple.os == .linux else { return triple.archName }

    // HACK: We don't wrap LLVM's ARM target architecture parsing, and we should
    //       definitely not try to port it. This check was only normalizing
    //       "armv7a/armv7r" and similar variants for armv6 to 'armv7' and
    //       'armv6', so just take a brute-force approach
    if triple.archName.contains("armv7") { return "armv7" }
    if triple.archName.contains("armv6") { return "armv6" }
    if triple.archName.contains("armv5") { return "armv5" }
    return triple.archName
  }

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
    let targetTriple = targetInfo.target.triple
    switch linkerOutputType {
    case .dynamicLibrary:
      // Same options as an executable, just with '-shared'
      commandLine.appendFlag("-shared")
      fallthrough
    case .executable:
      // Select the linker to use.
      if let arg = parsedOptions.getLastArgument(.useLd)?.asSingle {
        commandLine.appendFlag("--fuse-ld=\(arg)")
      } else if lto != nil {
        commandLine.appendFlag("--fuse-ld=lld")
      }

      if let arg = parsedOptions.getLastArgument(.ldPath)?.asSingle {
        commandLine.append(.joinedOptionAndPath("--ld-path=", try VirtualPath(path: arg)))
      }

      // Configure the toolchain.
      //
      // By default use the system `clang` to perform the link.  We use `clang` for
      // the driver here because we do not wish to select a particular C++ runtime.
      // Furthermore, until C++ interop is enabled, we cannot have a dependency on
      // C++ code from pure Swift code.  If linked libraries are C++ based, they
      // should properly link C++.  In the case of static linking, the user can
      // explicitly specify the C++ runtime to link against.  This is particularly
      // important for platforms like android where as it is a Linux platform, the
      // default C++ runtime is `libstdc++` which is unsupported on the target but
      // as the builds are usually cross-compiled from Linux, libstdc++ is going to
      // be present.  This results in linking the wrong version of libstdc++
      // generating invalid binaries.  It is also possible to use different C++
      // runtimes than the default C++ runtime for the platform (e.g. libc++ on
      // Windows rather than msvcprt).  When C++ interop is enabled, we will need to
      // surface this via a driver flag.  For now, opt for the simpler approach of
      // just using `clang` and avoid a dependency on the C++ runtime.
      var cxxCompatEnabled = parsedOptions.hasArgument(.enableExperimentalCxxInterop)
      if let cxxInteropMode = parsedOptions.getLastArgument(.cxxInteroperabilityMode) {
        if cxxInteropMode.asSingle == "swift-5.9" {
          cxxCompatEnabled = true
        }
      }

      let clangTool: Tool = cxxCompatEnabled ? .clangxx : .clang
      var clangPath = try getToolPath(clangTool)
      if let toolsDirPath = parsedOptions.getLastArgument(.toolsDirectory) {
        // FIXME: What if this isn't an absolute path?
        let toolsDir = try AbsolutePath(validating: toolsDirPath.asSingle)

        // If there is a clang in the toolchain folder, use that instead.
        if let tool = lookupExecutablePath(filename: cxxCompatEnabled
                                                        ? "clang++" : "clang",
                                           searchPaths: [toolsDir]) {
          clangPath = tool
        }

        // Look for binutils in the toolchain folder.
        commandLine.appendFlag("-B")
        commandLine.appendPath(toolsDir)
      }

      // Executables on Linux get -pie
      if targetTriple.os == .linux && linkerOutputType == .executable {
        commandLine.appendFlag("-pie")
      }

      let staticStdlib = parsedOptions.hasFlag(positive: .staticStdlib,
                                               negative: .noStaticStdlib,
                                                   default: false)
      let staticExecutable = parsedOptions.hasFlag(positive: .staticExecutable,
                                                   negative: .noStaticExecutable,
                                                  default: false)
      let isEmbeddedEnabled = parsedOptions.isEmbeddedEnabled

      let toolchainStdlibRpath = parsedOptions
                                 .hasFlag(positive: .toolchainStdlibRpath,
                                          negative: .noToolchainStdlibRpath,
                                          default: true)
      let hasRuntimeArgs = !(staticStdlib || staticExecutable || isEmbeddedEnabled)

      let runtimePaths = try runtimeLibraryPaths(
        for: targetInfo,
        parsedOptions: &parsedOptions,
        sdkPath: targetInfo.sdkPath?.path,
        isShared: hasRuntimeArgs
      )

      if hasRuntimeArgs && targetTriple.environment != .android &&
          toolchainStdlibRpath {
        // FIXME: We probably shouldn't be adding an rpath here unless we know
        //        ahead of time the standard library won't be copied.
        for path in runtimePaths {
          commandLine.appendFlag(.Xlinker)
          commandLine.appendFlag("-rpath")
          commandLine.appendFlag(.Xlinker)
          commandLine.appendPath(path)
        }
      }

      if !isEmbeddedEnabled && !parsedOptions.hasArgument(.nostartfiles) {
        let swiftrtPath = VirtualPath.lookup(targetInfo.runtimeResourcePath.path)
          .appending(
            components: targetTriple.platformName() ?? "",
            String(majorArchitectureName(for: targetTriple)),
            "swiftrt.o"
          )
        commandLine.appendPath(swiftrtPath)
      }

      // If we are linking statically, we need to add all
      // dependencies to a library search group to resolve
      // potential circular dependencies
      if staticStdlib || staticExecutable {
        commandLine.appendFlag(.Xlinker)
        commandLine.appendFlag("--start-group")
      }

      let inputFiles: [Job.ArgTemplate] = inputs.compactMap { input in
        // Autolink inputs are handled specially
        if input.type == .autolink {
          return .responseFilePath(input.file)
        } else if input.type == .object {
          return .path(input.file)
        } else if lto != nil && input.type == .llvmBitcode {
          return .path(input.file)
        } else {
          return nil
        }
      }
      commandLine.append(contentsOf: inputFiles)

      if staticStdlib || staticExecutable {
        commandLine.appendFlag(.Xlinker)
        commandLine.appendFlag("--end-group")
      }

      let fSystemArgs = parsedOptions.arguments(for: .F, .Fsystem)
      for opt in fSystemArgs {
        if opt.option == .Fsystem {
          commandLine.appendFlag("-iframework")
        } else {
          commandLine.appendFlag(.F)
        }
        commandLine.appendPath(try VirtualPath(path: opt.argument.asSingle))
      }

      if let path = targetInfo.sdkPath?.path {
        commandLine.appendFlag("--sysroot")
        commandLine.appendPath(VirtualPath.lookup(path))
      }

      // Add the runtime library link paths.
      for path in runtimePaths {
        commandLine.appendFlag(.L)
        commandLine.appendPath(path)
      }

      // Link the standard library. In two paths, we do this using a .lnk file
      // if we're going that route, we'll set `linkFilePath` to the path to that
      // file.
      var linkFilePath: VirtualPath? = VirtualPath.lookup(targetInfo.runtimeResourcePath.path)
        .appending(component: targetTriple.platformName() ?? "")

      if staticExecutable {
        linkFilePath = linkFilePath?.appending(component: "static-executable-args.lnk")
      } else if staticStdlib {
        linkFilePath = linkFilePath?.appending(component: "static-stdlib-args.lnk")
      } else {
        linkFilePath = nil
        if !isEmbeddedEnabled {
          commandLine.appendFlag("-lswiftCore")
        }
      }

      if let linkFile = linkFilePath {
        guard try fileSystem.exists(linkFile) else {
          fatalError("\(linkFile) not found")
        }
        commandLine.append(.responseFilePath(linkFile))
      }

      // Pass down an optimization level
      if let optArg = mapOptimizationLevelToClangArg(from: &parsedOptions) {
        commandLine.appendFlag(optArg)
      }

      // Explicitly pass the target to the linker
      commandLine.appendFlag("--target=\(targetTriple.triple)")

      // Delegate to Clang for sanitizers. It will figure out the correct linker
      // options.
      if linkerOutputType == .executable && !sanitizers.isEmpty {
        let sanitizerNames = sanitizers
          .map { $0.rawValue }
          .sorted() // Sort so we get a stable, testable order
          .joined(separator: ",")
        commandLine.appendFlag("-fsanitize=\(sanitizerNames)")

        // The TSan runtime depends on the blocks runtime and libdispatch.
        if sanitizers.contains(.thread) {
          commandLine.appendFlag("-lBlocksRuntime")
          commandLine.appendFlag("-ldispatch")
        }
      }

      if parsedOptions.hasArgument(.profileGenerate) {
        let libProfile = VirtualPath.lookup(targetInfo.runtimeResourcePath.path)
          .appending(components: "clang", "lib", targetTriple.osName,
                                 "libclang_rt.profile-\(targetTriple.archName).a")
        commandLine.appendPath(libProfile)

        // HACK: Hard-coded from llvm::getInstrProfRuntimeHookVarName()
        commandLine.appendFlag("-u__llvm_profile_runtime")
      }

      if let lto = lto {
        switch lto {
        case .llvmFull:
          commandLine.appendFlag("-flto=full")
        case .llvmThin:
          commandLine.appendFlag("-flto=thin")
        }
      }

      // Run clang++ in verbose mode if "-v" is set
      try commandLine.appendLast(.v, from: &parsedOptions)

      // These custom arguments should be right before the object file at the
      // end.
      try commandLine.appendAllExcept(
        includeList: [.linkerOption],
        excludeList: [.l],
        from: &parsedOptions
      )
      addLinkedLibArgs(to: &commandLine, parsedOptions: &parsedOptions)
      try addExtraClangLinkerArgs(to: &commandLine, parsedOptions: &parsedOptions)

      // This should be the last option, for convenience in checking output.
      commandLine.appendFlag(.o)
      commandLine.appendPath(outputFile)
      return try resolvedTool(clangTool, pathOverride: clangPath)
    case .staticLibrary:
      // We're using 'ar' as a linker
      commandLine.appendFlag("crs")
      commandLine.appendPath(outputFile)

      commandLine.append(contentsOf: inputs.lazy.filter {
                            lto == nil ? $0.type == .object
                                       : $0.type == .object || $0.type == .llvmBitcode
                         }.map { .path($0.file) })
      if targetTriple.environment == .android {
        // Always use the LTO archiver llvm-ar for Android
        return try resolvedTool(.staticLinker(.llvmFull))
      } else {
        return try resolvedTool(.staticLinker(lto))
      }
    }

  }
}
