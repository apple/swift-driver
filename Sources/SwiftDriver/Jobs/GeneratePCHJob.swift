//===--------------- GeneratePCHJob.swift - Generate PCH Job ----===//
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

extension Driver {
  mutating func generatePCHJob(input: TypedVirtualPath, output: TypedVirtualPath) throws -> Job {
    var inputs = [TypedVirtualPath]()
    var outputs = [TypedVirtualPath]()

    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }

    commandLine.appendFlag("-frontend")

    try addCommonFrontendOptions(
      commandLine: &commandLine, inputs: &inputs, bridgingHeaderHandling: .parsed)

    try commandLine.appendLast(.indexStorePath, from: &parsedOptions)

    // TODO: Should this just be pch output with extension changed?
    if parsedOptions.hasArgument(.serializeDiagnostics), let outputDirectory = parsedOptions.getLastArgument(.pchOutputDir)?.asSingle {
      commandLine.appendFlag(.serializeDiagnosticsPath)
      let path: VirtualPath
      if let outputPath = outputFileMap?.existingOutput(inputFile: input.fileHandle, outputType: .diagnostics) {
        path = VirtualPath.lookup(outputPath)
      } else if let modulePath = parsedOptions.getLastArgument(.emitModulePath) {
        // TODO: does this hash need to be persistent?
        let code = UInt(bitPattern: modulePath.asSingle.hashValue)
        let outputName = input.file.basenameWithoutExt + "-" + String(code, radix: 36)
        path = try VirtualPath(path: outputDirectory).appending(component: outputName.appendingFileTypeExtension(.diagnostics))
      } else {
        // FIXME: should have '-.*' at the end of the filename, similar to llvm::sys::fs::createTemporaryFile
        path = .temporary(RelativePath(input.file.basenameWithoutExt.appendingFileTypeExtension(.diagnostics)))
      }
      commandLine.appendPath(path)
      outputs.append(.init(file: path.intern(), type: .diagnostics))
    }

    inputs.append(input)
    commandLine.appendPath(input.file)

    try commandLine.appendLast(.indexStorePath, from: &parsedOptions)

    commandLine.appendFlag(.emitPch)

    if parsedOptions.hasArgument(.pchOutputDir) {
      try commandLine.appendLast(.pchOutputDir, from: &parsedOptions)
    } else {
      commandLine.appendFlag(.o)
      commandLine.appendPath(output.file)
    }
    outputs.append(output)

    return Job(
      moduleName: moduleOutputInfo.name,
      kind: .generatePCH,
      tool: try toolchain.getToolPathHandle(.swiftCompiler),
      commandLine: commandLine,
      displayInputs: [],
      inputs: inputs,
      primaryInputs: [],
      outputs: outputs,
      supportsResponseFiles: true
    )
  }
}
