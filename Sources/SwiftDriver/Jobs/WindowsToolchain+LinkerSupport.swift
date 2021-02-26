//===---------------- WindowsToolchain+LinkerSupport.swift ----------------===//
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
import TSCBasic
import SwiftOptions

extension WindowsToolchain {
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
    let targetTriple = targetInfo.target.triple

    switch linkerOutputType {
    case .dynamicLibrary:
      commandLine.appendFlags("-shared")
      fallthrough
    case .executable:
      if !targetTriple.triple.isEmpty {
        commandLine.appendFlag("-target")
        commandLine.appendFlag(targetTriple.triple)
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
      var clangPath = try getToolPath(.clang)
      if let toolsDirPath = parsedOptions.getLastArgument(.toolsDirectory) {
        // FIXME: What if this isn't an absolute path?
        let toolsDir = try AbsolutePath(validating: toolsDirPath.asSingle)

        // If there is a clang in the toolchain folder, use that instead.
        if let tool = lookupExecutablePath(filename: "clang.exe", searchPaths: [toolsDir]) {
          clangPath = tool
        }

        // Look for binutils in the toolchain folder.
        commandLine.appendFlag("-B")
        commandLine.appendPath(toolsDir)
      }

      let linker: String
      if let arg = parsedOptions.getLastArgument(.useLd) {
        linker = arg.asSingle
      } else {
        linker = "link"
      }
      commandLine.appendFlag("-fuse-ld=\(linker)")

      // Rely on `-libc` to correctly identify the MSVC Runtime Library.  We use
      // `-nostartfiles` as that limits the difference to just the
      // `-defaultlib:libcmt` which is passed unconditionally with the `clang`
      // driver rather than the `clang-cl` driver.
      commandLine.appendFlag("-nostartfiles")
      if let crt = parsedOptions.getLastArgument(.libc) {
        switch crt.asSingle {
        case "MT", "MultiThreaded", "static-ucrt":
          commandLine.appendFlags("-Xlinker", "-defaultlib:libcmt")
        case "MTd", "MultiThreadedDebug", "static-debug-ucrt":
          commandLine.appendFlags("-Xlinker", "-defaultlib:libcmtd")
        case "MD", "MultiThreadedDLL", "shared-ucrt":
          commandLine.appendFlags("-Xlinker", "-defaultlib:msvcrt")
        case "MDd", "MultiThreadedDebugDLL", "shared-debug-ucrt":
          commandLine.appendFlags("-Xlinker", "-defaultlib:msvcrtd")
        default:
          throw ToolchainValidationError.illegalCrtName(crt.asSingle)
        }
      } else {
        // NOTE: default to `/MD` like Visual Studio 2015 and newer.
        // This is far more useful of a mode since the `/MT` mode requires
        // that everything is statically linked.
        commandLine.appendFlags("-Xlinker", "-defaultlib:msvcrt")
      }

      let staticStdlib = parsedOptions.hasFlag(positive: .staticStdlib,
                                               negative: .noStaticStdlib,
                                                default: false)
      let staticExecutable = parsedOptions.hasFlag(positive: .staticExecutable,
                                                   negative: .noStaticExecutable,
                                                    default: false)
      let hasRuntimeArgs = !(staticStdlib || staticExecutable)

      let runtimePaths = try runtimeLibraryPaths(
        for: targetInfo,
        parsedOptions: &parsedOptions,
        sdkPath: targetInfo.sdkPath?.path,
        isShared: hasRuntimeArgs
      )

      guard let swiftrtPath = targetInfo.sdkPath?.path
        .appending(
          components: "usr", "lib", "swift", "windows",
          targetTriple.archName,
          "swiftrt.obj") else {
        throw ToolchainValidationError.sdkNotFound
      }
      commandLine.appendPath(swiftrtPath)

      let inputFiles: [Job.ArgTemplate] = inputs.compactMap { input in
        // Autolink inputs are handled specially
        if input.type == .autolink {
          return .responseFilePath(input.file)
        } else if input.type == .object {
          return .path(input.file)
        } else {
          return nil
        }
      }
      commandLine.append(contentsOf: inputFiles)

      let fSystemArgs = parsedOptions.arguments(for: .F, .Fsystem)
      for opt in fSystemArgs {
        if opt.option == .Fsystem {
          commandLine.appendFlag("-iframework")
        } else {
          commandLine.appendFlag(.F)
        }
        commandLine.appendPath(try VirtualPath(path: opt.argument.asSingle))
      }

      // Add the runtime library link paths.
      for path in runtimePaths {
        commandLine.appendFlag(.L)
        commandLine.appendPath(path.appending(component: targetTriple.archName))
      }

      if hasRuntimeArgs {
        commandLine.appendFlag("-lswiftCore")
      }

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

      // Run clang in verbose mode if "-v" is set
      try commandLine.appendLast(.v, from: &parsedOptions)

      // These custom arguments should be right before the object file at the
      // end.
      try commandLine.append(
        contentsOf: parsedOptions.arguments(in: .linkerOption)
      )
      try commandLine.appendAllArguments(.Xlinker, from: &parsedOptions)
      try commandLine.appendAllArguments(.XclangLinker, from: &parsedOptions)

      // This should be the last option, for convenience in checking output.
      commandLine.appendFlag(.o)
      commandLine.appendPath(outputFile)
      return clangPath
    case .staticLibrary:
      commandLine.appendFlags("-nologo")
      commandLine.append(.joinedOptionAndPath("-out:", outputFile))
      commandLine.append(contentsOf: inputs.map { .path($0.file) })
      return try getToolPath(.staticLinker(lto))
    }
  }
}
