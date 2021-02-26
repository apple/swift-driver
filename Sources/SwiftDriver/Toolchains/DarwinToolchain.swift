//===--------------- DarwinToolchain.swift - Swift Darwin Toolchain -------===//
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
import Foundation
import SwiftOptions

/// Toolchain for Darwin-based platforms, such as macOS and iOS.
///
/// FIXME: This class is not thread-safe.
@_spi(Testing) public final class DarwinToolchain: Toolchain {
  public let env: [String: String]

  /// The executor used to run processes used to find tools and retrieve target info.
  public let executor: DriverExecutor

  /// The file system to use for any file operations.
  public let fileSystem: FileSystem

  // An externally provided path from where we should find compiler
  public let compilerExecutableDir: AbsolutePath?

  /// Doubles as path cache and point for overriding normal lookup
  private var toolPaths = [Tool: AbsolutePath]()

  // An externally provided path from where we should find tools like ld
  public let toolDirectory: AbsolutePath?

  public let dummyForTestingObjectFormat = Triple.ObjectFormat.macho

  public init(env: [String: String], executor: DriverExecutor, fileSystem: FileSystem = localFileSystem,
              compilerExecutableDir: AbsolutePath? = nil, toolDirectory: AbsolutePath? = nil) {
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
    case .dynamicLinker:
      return try lookup(executable: "ld")
    case .staticLinker:
      return try lookup(executable: "libtool")
    case .dsymutil:
      return try lookup(executable: "dsymutil")
    case .clang:
      return try lookup(executable: "clang")
    case .swiftAutolinkExtract:
      return try lookup(executable: "swift-autolink-extract")
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

  /// Path to the StdLib inside the SDK.
  public func sdkStdlib(sdk: AbsolutePath) -> AbsolutePath {
    sdk.appending(RelativePath("usr/lib/swift"))
  }

  public func makeLinkerOutputFilename(moduleName: String, type: LinkOutputType) -> String {
    switch type {
    case .executable: return moduleName
    case .dynamicLibrary: return "lib\(moduleName).dylib"
    case .staticLibrary: return "lib\(moduleName).a"
    }
  }

  public func defaultSDKPath(_ target: Triple?) throws -> AbsolutePath? {
    let hostIsMacOS: Bool
    #if os(macOS)
    hostIsMacOS = true
    #else
    hostIsMacOS = false
    #endif

    if target?.isMacOSX == true || hostIsMacOS {
      let result = try executor.checkNonZeroExit(
        args: "xcrun", "-sdk", "macosx", "--show-sdk-path",
        environment: env
      ).spm_chomp()
      return AbsolutePath(result)
    }

    return nil
  }

  public var shouldStoreInvocationInDebugInfo: Bool {
    // This matches the behavior in Clang.
    !(env["RC_DEBUG_OPTIONS"]?.isEmpty ?? true)
  }

  public func runtimeLibraryName(
    for sanitizer: Sanitizer,
    targetTriple: Triple,
    isShared: Bool
  ) throws -> String {
    return """
    libclang_rt.\(sanitizer.libraryName)_\
    \(targetTriple.darwinPlatform!.libraryNameSuffix)\
    \(isShared ? "_dynamic.dylib" : ".a")
    """
  }

  public enum ToolchainValidationError: Error, DiagnosticData {
    case osVersionBelowMinimumDeploymentTarget(String)
    case argumentNotSupported(String)
    case iOSVersionAboveMaximumDeploymentTarget(Int)
    case unsupportedTargetVariant(variant: Triple)
    case darwinOnlySupportsLibCxx

    public var description: String {
      switch self {
      case .osVersionBelowMinimumDeploymentTarget(let target):
        return "Swift requires a minimum deployment target of \(target)"
      case .iOSVersionAboveMaximumDeploymentTarget(let version):
        return "iOS \(version) does not support 32-bit programs"
      case .unsupportedTargetVariant(variant: let variant):
        return "unsupported '\(variant.isiOS ? "-target-variant" : "-target")' value '\(variant.triple)'; use 'ios-macabi' instead"
      case .argumentNotSupported(let argument):
        return "\(argument) is no longer supported for Apple platforms"
      case .darwinOnlySupportsLibCxx:
        return "The only C++ standard library supported on Apple platforms is libc++"
      }
    }
  }

  public func validateArgs(_ parsedOptions: inout ParsedOptions,
                           targetTriple: Triple,
                           targetVariantTriple: Triple?,
                           diagnosticsEngine: DiagnosticsEngine) throws {
    // Validating arclite library path when link-objc-runtime.
    validateLinkObjcRuntimeARCLiteLib(&parsedOptions,
                                      targetTriple: targetTriple,
                                      diagnosticsEngine: diagnosticsEngine)
    // Validating apple platforms deployment targets.
    try validateDeploymentTarget(&parsedOptions, targetTriple: targetTriple)
    if let targetVariantTriple = targetVariantTriple,
       !targetTriple.isValidForZipperingWithTriple(targetVariantTriple) {
      throw ToolchainValidationError.unsupportedTargetVariant(variant: targetVariantTriple)
    }
    // Validating darwin unsupported -static-stdlib argument.
    if parsedOptions.hasArgument(.staticStdlib) {
        throw ToolchainValidationError.argumentNotSupported("-static-stdlib")
    }
    // If a C++ standard library is specified, it has to be libc++.
    if let cxxLib = parsedOptions.getLastArgument(.experimentalCxxStdlib) {
        if cxxLib.asSingle != "libc++" {
            throw ToolchainValidationError.darwinOnlySupportsLibCxx
        }
    }
  }

  func validateDeploymentTarget(_ parsedOptions: inout ParsedOptions,
                                targetTriple: Triple) throws {
    // Check minimum supported OS versions.
    if targetTriple.isMacOSX,
       targetTriple.version(for: .macOS) < Triple.Version(10, 9, 0) {
      throw ToolchainValidationError.osVersionBelowMinimumDeploymentTarget("OS X 10.9")
    }
    // tvOS triples are also iOS, so check it first.
    else if targetTriple.isTvOS,
            targetTriple.version(for: .tvOS(.device)) < Triple.Version(9, 0, 0) {
      throw ToolchainValidationError.osVersionBelowMinimumDeploymentTarget("tvOS 9.0")
    } else if targetTriple.isiOS {
      if targetTriple.version(for: .iOS(.device)) < Triple.Version(7, 0, 0) {
        throw ToolchainValidationError.osVersionBelowMinimumDeploymentTarget("iOS 7")
      }
      if targetTriple.arch?.is32Bit == true,
         targetTriple.version(for: .iOS(.device)) >= Triple.Version(11, 0, 0) {
        throw ToolchainValidationError.iOSVersionAboveMaximumDeploymentTarget(targetTriple.version(for: .iOS(.device)).major)
      }
    } else if targetTriple.isWatchOS,
              targetTriple.version(for: .watchOS(.device)) < Triple.Version(2, 0, 0) {
      throw ToolchainValidationError.osVersionBelowMinimumDeploymentTarget("watchOS 2.0")
    }
  }
    
  func validateLinkObjcRuntimeARCLiteLib(_ parsedOptions: inout ParsedOptions,
                                           targetTriple: Triple,
                                           diagnosticsEngine: DiagnosticsEngine) {
    if parsedOptions.hasFlag(positive: .linkObjcRuntime, negative: .noLinkObjcRuntime, default: targetTriple.supports(.compatibleObjCRuntime)) {
        guard let _ = try? findARCLiteLibPath() else {
            diagnosticsEngine.emit(.warn_arclite_not_found_when_link_objc_runtime)
            return
        }
    }
  }

  struct DarwinSDKInfo: Decodable {
    private enum CodingKeys: String, CodingKey {
      case version = "Version"
      case versionMap = "VersionMap"
    }

    struct VersionMap: Decodable {
      private enum CodingKeys: String, CodingKey {
        case macOSToCatalystMapping = "macOS_iOSMac"
      }

      var macOSToCatalystMapping: [Version: Version]

      init(from decoder: Decoder) throws {
        let keyedContainer = try decoder.container(keyedBy: CodingKeys.self)

        let mappingDict = try keyedContainer.decode([String: String].self, forKey: .macOSToCatalystMapping)
        self.macOSToCatalystMapping = [:]
        try mappingDict.forEach { key, value in
          guard let newKey = Version(potentiallyIncompleteVersionString: key) else {
            throw DecodingError.dataCorruptedError(forKey: .macOSToCatalystMapping,
                                                   in: keyedContainer,
                                                   debugDescription: "Malformed version string")
          }
          guard let newValue = Version(potentiallyIncompleteVersionString: value) else {
            throw DecodingError.dataCorruptedError(forKey: .macOSToCatalystMapping,
                                                   in: keyedContainer,
                                                   debugDescription: "Malformed version string")
          }
          self.macOSToCatalystMapping[newKey] = newValue
        }
      }
    }

    private var version: Version
    private var versionMap: VersionMap

    init(from decoder: Decoder) throws {
      let keyedContainer = try decoder.container(keyedBy: CodingKeys.self)

      let versionString = try keyedContainer.decode(String.self, forKey: .version)
      guard let version = Version(potentiallyIncompleteVersionString: versionString) else {
        throw DecodingError.dataCorruptedError(forKey: .version,
                                               in: keyedContainer,
                                               debugDescription: "Malformed version string")
      }
      self.version = version
      self.versionMap = try keyedContainer.decode(VersionMap.self, forKey: .versionMap)
    }

    func sdkVersion(for triple: Triple) -> Version {
      if triple.isMacCatalyst {
        // For the Mac Catalyst environment, we have a macOS SDK with a macOS
        // SDK version. Map that to the corresponding iOS version number to pass
        // down to the linker.
        return versionMap.macOSToCatalystMapping[version.withoutBuildNumbers] ?? Version(0, 0, 0)
      }
      return version
    }
  }

  // SDK info is computed lazily. This should not generally be accessed directly.
  private var _sdkInfo: DarwinSDKInfo? = nil

  func getTargetSDKInfo(sdkPath: VirtualPath) -> DarwinSDKInfo? {
    if let info = _sdkInfo {
      return info
    } else {
      let sdkSettingsPath = sdkPath.appending(component: "SDKSettings.json")
      guard let contents = try? fileSystem.readFileContents(sdkSettingsPath) else { return nil }
      guard let sdkInfo = try? JSONDecoder().decode(DarwinSDKInfo.self,
                                                    from: Data(contents.contents)) else { return nil }
      self._sdkInfo = sdkInfo
      return sdkInfo
    }
  }

  public func addPlatformSpecificCommonFrontendOptions(
    commandLine: inout [Job.ArgTemplate],
    inputs: inout [TypedVirtualPath],
    frontendTargetInfo: FrontendTargetInfo
  ) throws {
    guard let sdkPath = frontendTargetInfo.sdkPath?.path,
          let sdkInfo = getTargetSDKInfo(sdkPath: sdkPath) else { return }

    commandLine.append(.flag("-target-sdk-version"))
    commandLine.append(.flag(sdkInfo.sdkVersion(for: frontendTargetInfo.target.triple).description))

    if let targetVariantTriple = frontendTargetInfo.targetVariant?.triple {
      commandLine.append(.flag("-target-variant-sdk-version"))
      commandLine.append(.flag(sdkInfo.sdkVersion(for: targetVariantTriple).description))
    }
  }
}

extension Diagnostic.Message {
    static var warn_arclite_not_found_when_link_objc_runtime: Diagnostic.Message {
      .warning(
        "unable to find Objective-C runtime support library 'arclite'; " +
        "pass '-no-link-objc-runtime' to silence this warning"
      )
    }
}
