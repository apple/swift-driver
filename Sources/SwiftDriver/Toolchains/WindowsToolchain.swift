//===--------- WindowsToolchain.swift - Swift Windows Toolchain -----------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import TSCBasic
import SwiftOptions

/// Toolchain for Windows.
@_spi(Testing) public final class WindowsToolchain: Toolchain {
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

  public let dummyForTestingObjectFormat = Triple.ObjectFormat.coff

  public init(env: [String: String], executor: DriverExecutor, fileSystem: FileSystem = localFileSystem, compilerExecutableDir: AbsolutePath? = nil, toolDirectory: AbsolutePath? = nil) {
    self.env = env
    self.executor = executor
    self.fileSystem = fileSystem
    self.compilerExecutableDir = compilerExecutableDir
    self.toolDirectory = toolDirectory
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
    case .staticLinker:
      return try lookup(executable: "lib")
    case .dynamicLinker:
      return try lookup(executable: "link")
    case .clang:
      return try lookup(executable: "clang")
    case .swiftAutolinkExtract:
      return try lookup(executable: "swift-autolink-extract")
    case .dsymutil:
      return try lookup(executable: "llvm-dsymutil")
    case .lldb:
      return try lookup(executable: "lldb")
    case .dwarfdump:
      return try lookup(executable: "llvm-dwarfdump")
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

  /// Path to the StdLib inside the SDK.
  public func sdkStdlib(sdk: AbsolutePath, triple: Triple) -> AbsolutePath {
    sdk.appending(RelativePath("usr/lib/swift/windows")).appending(component: triple.archName)
  }

  public func makeLinkerOutputFilename(moduleName: String, type: LinkOutputType) -> String {
    switch type {
    case .executable: return "\(moduleName).exe"
    case .dynamicLibrary: return "\(moduleName).dll"
    case .staticLibrary: return "lib\(moduleName).lib"
    }
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
    return "clang_rt.\(sanitizer.libraryName)-\(targetTriple.archName).lib"
  }
}

extension WindowsToolchain {
  public func validateArgs(_ parsedOptions: inout ParsedOptions,
                           targetTriple: Triple,
                           targetVariantTriple: Triple?,
                           diagnosticsEngine: DiagnosticsEngine) throws {
    // The default linker `LINK.exe` can use `/LTCG:INCREMENTAL` to enable LTO,
    // and LLVM LTOs are available through `lld-link`. Both LTO methods still need
    // additional work to be integrated, so disable this option for now.
    if parsedOptions.hasArgument(.lto) {
      // TODO: LTO support on Windows
      throw ToolchainValidationError.argumentNotSupported("-lto=")
    }
    // Windows executables should be profiled with ETW, whose support needs to be
    // implemented before we can enable the option.
    if parsedOptions.hasArgument(.profileGenerate) {
      throw ToolchainValidationError.argumentNotSupported("-profile-generate")
    }
    if parsedOptions.hasArgument(.profileUse) {
      throw ToolchainValidationError.argumentNotSupported("-profile-use=")
    }
  }

  public enum ToolchainValidationError: Error, DiagnosticData {
    case argumentNotSupported(String)
    case illegalCrtName(String)
    case sdkNotFound

    public var description: String {
      switch self {
      case .argumentNotSupported(let argument):
        return "\(argument) is not supported for Windows"
      case .illegalCrtName(let argument):
        return "\(argument) is not a valid C Runtime for Windows"
      case .sdkNotFound:
        return "swift development on Windows always requires the SDK of target platform"
      }
    }
  }
}
