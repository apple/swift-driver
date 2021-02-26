//===----- Toolchain+InterpreterSupport.swift - Swift Interpreter Support -===//
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
//
import TSCBasic
import SwiftOptions

extension Toolchain {
  func addPathEnvironmentVariableIfNeeded(
    _ environmentVariable: String,
    to env: inout [String : String],
    currentEnv: [String: String],
    option: Option,
    parsedOptions: inout ParsedOptions,
    extraPaths: [String] = []
    ) {
    let argPaths = parsedOptions.arguments(for: option)
    guard !argPaths.isEmpty || !extraPaths.isEmpty else { return }

    env[environmentVariable] = (argPaths.map({ $0.argument.asSingle }) +
      extraPaths + [currentEnv[environmentVariable]]).compactMap{ $0 }.joined(separator: ":")
  }
}

extension DarwinToolchain {
  public func platformSpecificInterpreterEnvironmentVariables(
    env: [String : String],
    parsedOptions: inout ParsedOptions,
    sdkPath: VirtualPath?,
    targetInfo: FrontendTargetInfo) throws -> [String: String] {
    var envVars: [String: String] = [:]

    let runtimePaths = try runtimeLibraryPaths(
      for: targetInfo,
      parsedOptions: &parsedOptions,
      sdkPath: sdkPath,
      isShared: true
    ).map { $0.name }

    addPathEnvironmentVariableIfNeeded("DYLD_LIBRARY_PATH", to: &envVars,
                                       currentEnv: env, option: .L,
                                       parsedOptions: &parsedOptions,
                                       extraPaths: runtimePaths)

    addPathEnvironmentVariableIfNeeded("DYLD_FRAMEWORK_PATH", to: &envVars,
                                       currentEnv: env, option: .F,
                                       parsedOptions: &parsedOptions)

    return envVars
  }
}

extension GenericUnixToolchain {
  public func platformSpecificInterpreterEnvironmentVariables(
    env: [String : String],
    parsedOptions: inout ParsedOptions,
    sdkPath: VirtualPath?,
    targetInfo: FrontendTargetInfo) throws -> [String: String] {
    var envVars: [String: String] = [:]

    let runtimePaths = try runtimeLibraryPaths(
      for: targetInfo,
      parsedOptions: &parsedOptions,
      sdkPath: sdkPath,
      isShared: true
    ).map { $0.name }

    addPathEnvironmentVariableIfNeeded("LD_LIBRARY_PATH", to: &envVars,
                                       currentEnv: env, option: .L,
                                       parsedOptions: &parsedOptions,
                                       extraPaths: runtimePaths)

    return envVars
  }
}

extension WindowsToolchain {
  public func platformSpecificInterpreterEnvironmentVariables(
    env: [String : String],
    parsedOptions: inout ParsedOptions,
    sdkPath: VirtualPath?,
    targetInfo: FrontendTargetInfo) throws -> [String: String] {
    // TODO: See whether Windows needs `platformSpecificInterpreterEnvironmentVariables`
    return [:]
  }
}
