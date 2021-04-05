//===--------------- InterpretJob.swift - Swift Immediate Mode ------------===//
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
  mutating func interpretJob(inputs allInputs: [TypedVirtualPath]) throws -> Job {
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }
    var inputs: [TypedVirtualPath] = []

    commandLine.appendFlags("-frontend", "-interpret")

    // Add the inputs.
    for input in allInputs {
      commandLine.append(.path(input.file))
      inputs.append(input)
    }

    if parsedOptions.hasArgument(.parseStdlib) {
      commandLine.appendFlag(.disableObjcAttrRequiresFoundationModule)
    }

    try addCommonFrontendOptions(commandLine: &commandLine, inputs: &inputs)
    // FIXME: MSVC runtime flags

    try commandLine.appendLast(.parseSil, from: &parsedOptions)
    try commandLine.appendAll(.l, .framework, from: &parsedOptions)

    // The immediate arguments must be last.
    try commandLine.appendLast(.DASHDASH, from: &parsedOptions)

    let extraEnvironment = try toolchain.platformSpecificInterpreterEnvironmentVariables(
      env: self.env, parsedOptions: &parsedOptions,
      sdkPath: frontendTargetInfo.sdkPath?.path, targetInfo: self.frontendTargetInfo)

    return Job(
      moduleName: moduleOutputInfo.name,
      kind: .interpret,
      tool: try toolchain.getToolPathHandle(.swiftCompiler),
      commandLine: commandLine,
      inputs: inputs,
      primaryInputs: [],
      outputs: [],
      extraEnvironment: extraEnvironment,
      requiresInPlaceExecution: true,
      supportsResponseFiles: true
    )
  }
}
