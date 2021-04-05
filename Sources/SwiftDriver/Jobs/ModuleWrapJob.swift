//===--------------- ModuleWrapJob.swift - Swift Module Wrapping ----------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

extension Driver {
  mutating func moduleWrapJob(moduleInput: TypedVirtualPath) throws -> Job {
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }

    commandLine.appendFlags("-modulewrap")

    // Add the input.
    commandLine.append(.path(moduleInput.file))
    assert(compilerOutputType == .object, "-modulewrap mode only produces object files")

    commandLine.appendFlags("-target", targetTriple.triple)

    let outputPath = moduleInput.file.replacingExtension(with: .object)
    commandLine.appendFlag("-o")
    commandLine.appendPath(outputPath)

    return Job(
      moduleName: moduleOutputInfo.name,
      kind: .moduleWrap,
      tool: try toolchain.getToolPathHandle(.swiftCompiler),
      commandLine: commandLine,
      inputs: [moduleInput],
      primaryInputs: [],
      outputs: [.init(file: outputPath.intern(), type: .object)],
      supportsResponseFiles: true
    )
  }
}
