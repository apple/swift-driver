//===--------------- BackendJob.swift - Swift Backend Job -------------===//
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

import Foundation

extension Driver {
  /// Form a backend job.
  mutating func backendJob(input: TypedVirtualPath,
                           addJobOutputs: ([TypedVirtualPath]) -> Void)
  throws -> Job {
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }
    var inputs = [TypedVirtualPath]()
    var outputs = [TypedVirtualPath]()

    commandLine.appendFlag("-frontend")
    addCompileModeOption(outputType: compilerOutputType, commandLine: &commandLine)

    // Add input arguments.
    commandLine.appendFlag(.primaryFile)
    commandLine.appendPath(input.file)
    inputs.append(input)

    commandLine.appendFlag(.embedBitcode)

    // -embed-bitcode only supports a restricted set of flags.
    commandLine.appendFlag(.target)
    commandLine.appendFlag(targetTriple.triple)

    // Enable address top-byte ignored in the ARM64 backend.
    if targetTriple.arch == .aarch64 {
      commandLine.appendFlag(.Xllvm)
      commandLine.appendFlag("-aarch64-use-tbi")
    }

    // Handle the CPU and its preferences.
    try commandLine.appendLast(.targetCpu, from: &parsedOptions)

    // Enable optimizations, but disable all LLVM-IR-level transformations.
    try commandLine.appendLast(in: .O, from: &parsedOptions)
    commandLine.appendFlag(.disableLlvmOptzns)

    try commandLine.appendLast(.parseStdlib, from: &parsedOptions)

    commandLine.appendFlag(.moduleName)
    commandLine.appendFlag(moduleOutputInfo.name)

    // Add the output file argument if necessary.
    if let compilerOutputType = compilerOutputType {
      let output = computePrimaryOutput(for: input,
                                        outputType: compilerOutputType,
                                        isTopLevel: isTopLevelOutput(type: compilerOutputType))
      commandLine.appendFlag(.o)
      commandLine.appendPath(output.file)
      outputs.append(output)
    }

    addJobOutputs(outputs)

    return Job(
      moduleName: moduleOutputInfo.name,
      kind: .backend,
      tool: try toolchain.getToolPathHandle(.swiftCompiler),
      commandLine: commandLine,
      displayInputs: inputs,
      inputs: inputs,
      primaryInputs: [],
      outputs: outputs,
      supportsResponseFiles: true
    )
  }
}
