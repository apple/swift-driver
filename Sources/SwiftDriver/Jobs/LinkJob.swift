//===--------------- LinkJob.swift - Swift Linking Job --------------------===//
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

extension Driver {
  internal var relativeOutputFileForImage: RelativePath {
    if inputFiles.count == 1 && moduleOutputInfo.nameIsFallback && inputFiles[0].file != .standardInput {
      return RelativePath(inputFiles[0].file.basenameWithoutExt)
    }

    let outputName =
      toolchain.makeLinkerOutputFilename(moduleName: moduleOutputInfo.name,
                                         type: linkerOutputType!)
    return RelativePath(outputName)
  }

  /// Compute the output file for an image output.
  internal var outputFileForImage: VirtualPath {
    return useWorkingDirectory(relativeOutputFileForImage)
  }

  func useWorkingDirectory(_ relative: RelativePath) -> VirtualPath {
    return Driver.useWorkingDirectory(relative, workingDirectory)
  }

  static func useWorkingDirectory(_ relative: RelativePath, _ workingDirectory: AbsolutePath?) -> VirtualPath {
    if let wd = workingDirectory {
      return .absolute(AbsolutePath(relative.pathString, relativeTo: wd))
    }
    return .relative(relative)
  }

  /// Link the given inputs.
  mutating func linkJob(inputs: [TypedVirtualPath]) throws -> Job {
    var commandLine: [Job.ArgTemplate] = []

    // Compute the final output file
    let outputFile: VirtualPath
    if let output = parsedOptions.getLastArgument(.o) {
      outputFile = try VirtualPath(path: output.asSingle)
    } else {
      outputFile = outputFileForImage
    }

    // Defer to the toolchain for platform-specific linking
    let toolPath = try toolchain.addPlatformSpecificLinkerArgs(
      to: &commandLine,
      parsedOptions: &parsedOptions,
      linkerOutputType: linkerOutputType!,
      inputs: inputs,
      outputFile: outputFile,
      shouldUseInputFileList: shouldUseInputFileList,
      lto: lto,
      sanitizers: enabledSanitizers,
      targetInfo: frontendTargetInfo
    )

    // TODO: some, but not all, linkers support response files.
    return Job(
      moduleName: moduleOutputInfo.name,
      kind: .link,
      tool: VirtualPath.absolute(toolPath).intern(),
      commandLine: commandLine,
      displayInputs: inputs,
      inputs: inputs,
      primaryInputs: [],
      outputs: [.init(file: outputFile.intern(), type: .image)]
    )
  }
}
