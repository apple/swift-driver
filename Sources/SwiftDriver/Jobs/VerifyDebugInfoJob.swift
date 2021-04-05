//===------- VerifyDebugInfoJob.swift - Swift Debug Info Verification -----===//
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
  func verifyDebugInfoJob(inputs: [TypedVirtualPath]) throws -> Job {
    assert(inputs.count == 1)
    let input = inputs[0]

    // This mirrors the clang driver's --verify-debug-info option.
    var commandLine = [Job.ArgTemplate]()
    commandLine.appendFlags("--verify", "--debug-info", "--eh-frame", "--quiet")
    commandLine.appendPath(input.file)

    return Job(
      moduleName: moduleOutputInfo.name,
      kind: .verifyDebugInfo,
      tool: VirtualPath.absolute(try toolchain.getToolPath(.dwarfdump)).intern(),
      commandLine: commandLine,
      displayInputs: [],
      inputs: inputs,
      primaryInputs: [],
      outputs: []
    )
  }
}
