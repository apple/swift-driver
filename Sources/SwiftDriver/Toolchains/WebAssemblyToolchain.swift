//===-------- WebAssemblyToolchain.swift - Swift WASM Toolchain -----------===//
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
import TSCBasic
import SwiftOptions

/// Toolchain for WebAssembly-based systems.
@_spi(Testing) public final class WebAssemblyToolchain: Toolchain {
  @_spi(Testing) public enum Error: Swift.Error, DiagnosticData {
    case interactiveModeUnsupportedForTarget(String)
    case dynamicLibrariesUnsupportedForTarget(String)
    case sanitizersUnsupportedForTarget(String)
    case profilingUnsupportedForTarget(String)

    public var description: String {
      switch self {
      case .interactiveModeUnsupportedForTarget(let triple):
        return "interactive mode is unsupported for target '\(triple)'; use 'swiftc' instead"
      case .dynamicLibrariesUnsupportedForTarget(let triple):
        return "dynamic libraries are unsupported for target '\(triple)'"
      case .sanitizersUnsupportedForTarget(let triple):
        return "sanitizers are unsupported for target '\(triple)'"
      case .profilingUnsupportedForTarget(let triple):
        return "profiling is unsupported for target '\(triple)'"
      }
    }
  }

  public let env: [String: String]

  /// The executor used to run processes used to find tools and retrieve target info.
  public let executor: DriverExecutor

  /// The file system to use for queries.
  public let fileSystem: FileSystem

  // An externally provided path from where we should find compiler
  public let compilerExecutableDir: AbsolutePath?

  /// Doubles as path cache and point for overriding normal lookup
  private var toolPaths = [Tool: AbsolutePath]()

  // An externally provided path from where we should find tools like ld
  public let toolDirectory: AbsolutePath?

  public let dummyForTestingObjectFormat = Triple.ObjectFormat.wasm

  public init(env: [String: String], executor: DriverExecutor, fileSystem: FileSystem = localFileSystem, compilerExecutableDir: AbsolutePath? = nil, toolDirectory: AbsolutePath? = nil) {
    self.env = env
    self.executor = executor
    self.fileSystem = fileSystem
    self.compilerExecutableDir = compilerExecutableDir
    self.toolDirectory = toolDirectory
  }

  public func makeLinkerOutputFilename(moduleName: String, type: LinkOutputType) -> String {
    switch type {
    case .executable:
      return moduleName
    case .dynamicLibrary:
      // WASM doesn't support dynamic libraries yet, but we'll report the error later.
      return ""
    case .staticLibrary:
      return "lib\(moduleName).a"
    }
  }

  /// Retrieve the absolute path for a given tool.
  public func getToolPath(_ tool: Tool) throws -> AbsolutePath {
    // Check the cache
    if let toolPath = toolPaths[tool] {
      return toolPath
    }
    let path = try lookupToolPath(tool)
    // Cache the path
    toolPaths[tool] = path
    return path
  }

  private func lookupToolPath(_ tool: Tool) throws -> AbsolutePath {
    switch tool {
    case .swiftCompiler:
      return try lookup(executable: "swift-frontend")
    case .staticLinker(nil):
      return try lookup(executable: "ar")
    case .staticLinker(.llvmFull),
         .staticLinker(.llvmThin):
      return try lookup(executable: "llvm-ar")
    case .dynamicLinker:
      // FIXME: This needs to look in the tools_directory first.
      return try lookup(executable: "clang")
    case .clang:
      return try lookup(executable: "clang")
    case .swiftAutolinkExtract:
      return try lookup(executable: "swift-autolink-extract")
    case .dsymutil:
      return try lookup(executable: "dsymutil")
    case .lldb:
      return try lookup(executable: "lldb")
    case .dwarfdump:
      return try lookup(executable: "dwarfdump")
    case .swiftHelp:
      return try lookup(executable: "swift-help")
    }
  }

  public func overrideToolPath(_ tool: Tool, path: AbsolutePath) {
    toolPaths[tool] = path
  }

  public func clearKnownToolPath(_ tool: Tool) {
    toolPaths.removeValue(forKey: tool)
  }

  public func defaultSDKPath(_ target: Triple?) throws -> AbsolutePath? {
    return nil
  }

  public var shouldStoreInvocationInDebugInfo: Bool { false }

  public func runtimeLibraryName(
    for sanitizer: Sanitizer,
    targetTriple: Triple,
    isShared: Bool
  ) throws -> String {
    throw Error.sanitizersUnsupportedForTarget(targetTriple.triple)
  }

  public func platformSpecificInterpreterEnvironmentVariables(env: [String : String],
                                                              parsedOptions: inout ParsedOptions,
                                                              sdkPath: VirtualPath?,
                                                              targetInfo: FrontendTargetInfo) throws -> [String : String] {
    throw Error.interactiveModeUnsupportedForTarget(targetInfo.target.triple.triple)
  }
}
