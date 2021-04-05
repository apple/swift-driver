//===- VerifyModuleInterface.swift - Swift Module Interface Verification --===//
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
  mutating func verifyModuleInterfaceJob(interfaceInput: TypedVirtualPath) throws -> Job {
    var commandLine: [Job.ArgTemplate] = swiftCompilerPrefixArgs.map { Job.ArgTemplate.flag($0) }
    var inputs: [TypedVirtualPath] = [interfaceInput]
    commandLine.appendFlags("-frontend", "-typecheck-module-from-interface")
    commandLine.appendPath(interfaceInput.file)
    try addCommonFrontendOptions(commandLine: &commandLine, inputs: &inputs)
    // FIXME: MSVC runtime flags

    // Compute the serialized diagnostics output file
    let outputFile: TypedVirtualPath
    if let output = serializedDiagnosticsFilePath {
      outputFile = TypedVirtualPath(file: output, type: .diagnostics)
    } else {
      outputFile = TypedVirtualPath(file: interfaceInput.file.replacingExtension(with: .diagnostics).intern(),
                                    type: .diagnostics)
    }

    return Job(
      moduleName: moduleOutputInfo.name,
      kind: .verifyModuleInterface,
      tool: try toolchain.getToolPathHandle(.swiftCompiler),
      commandLine: commandLine,
      displayInputs: [interfaceInput],
      inputs: inputs,
      primaryInputs: [],
      outputs: [outputFile]
    )
  }
}
