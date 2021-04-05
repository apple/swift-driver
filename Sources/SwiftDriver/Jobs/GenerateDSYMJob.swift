//===--------------- GenerateDSYMJob.swift - Swift dSYM Generation --------===//
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
  mutating func generateDSYMJob(inputs: [TypedVirtualPath]) throws -> Job {
    assert(inputs.count == 1)
    let input = inputs[0]

    // Output is final output file + `.dSYM`
    let outputFile: VirtualPath
    if let output = parsedOptions.getLastArgument(.o) {
      outputFile = try VirtualPath(path: output.asSingle)
    } else {
      outputFile = outputFileForImage
    }
    let outputPath = try VirtualPath(path: outputFile.description.appendingFileTypeExtension(.dSYM))

    var commandLine = [Job.ArgTemplate]()
    commandLine.appendPath(input.file)

    commandLine.appendFlag(.o)
    commandLine.appendPath(outputPath)

    return Job(
      moduleName: moduleOutputInfo.name,
      kind: .generateDSYM,
      tool: try toolchain.getToolPathHandle(.dsymutil),
      commandLine: commandLine,
      displayInputs: [],
      inputs: inputs,
      primaryInputs: [],
      outputs: [.init(file: outputPath.intern(), type: .dSYM)]
    )
  }
}
