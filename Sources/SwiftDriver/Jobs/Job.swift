//===--------------- Job.swift - Swift Job Abstraction --------------------===//
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
import Foundation

/// A job represents an individual subprocess that should be invoked during compilation.
public struct Job: Codable, Equatable, Hashable {
  public enum Kind: String, Codable {
    case compile
    case backend
    case mergeModule = "merge-module"
    case link
    case generateDSYM = "generate-dSYM"
    case autolinkExtract = "autolink-extract"
    case emitModule = "emit-module"
    case generatePCH = "generate-pch"
    case moduleWrap = "module-wrap"

    /// Generate a compiled Clang module.
    case generatePCM = "generate-pcm"
    case interpret
    case repl
    case verifyDebugInfo = "verify-debug-info"
    case printTargetInfo = "print-target-info"
    case emitSupportedFeatures = "emit-supported-features"
    case versionRequest = "version-request"
    case scanDependencies = "scan-dependencies"
    case verifyModuleInterface = "verify-emitted-module-interface"
    case help
  }

  public enum ArgTemplate: Equatable, Hashable {
    /// Represents a command-line flag that is substitued as-is.
    case flag(String)

    /// Represents a virtual path on disk.
    case pathHandle(VirtualPath.Handle)

    /// Represents a response file path prefixed by '@'.
    case responseFilePathHandle(VirtualPath.Handle)

    /// Represents a joined option+path combo.
    case joinedOptionAndPathHandle(String, VirtualPath.Handle)

    /// Represents a list of arguments squashed together and passed as a single argument.
    case squashedArgumentList(option: String, args: [ArgTemplate])

    public static func path(_ path: VirtualPath) -> ArgTemplate {
      return .pathHandle(path.intern())
    }

    public static func responseFilePath(_ path: VirtualPath) -> ArgTemplate {
      return .responseFilePathHandle(path.intern())
    }

    public static func joinedOptionAndPath(_ option: String, _ path: VirtualPath) -> ArgTemplate {
      return .joinedOptionAndPathHandle(option, path.intern())
    }
  }

  /// The Swift module this job involves.
  public var moduleName: String

  /// The tool to invoke.
  public var tool: VirtualPath.Handle

  /// The command-line arguments of the job.
  public var commandLine: [ArgTemplate]

  /// Whether or not the job supports using response files to pass command line arguments.
  public var supportsResponseFiles: Bool

  /// The list of inputs for this job. These are all files that must be provided in order for this job to execute,
  /// and this list, along with the corresponding `outputs` is used to establish producer-consumer dependency
  /// relationship among jobs.
  public var inputs: [TypedVirtualPath]

  /// The list of inputs to use for displaying purposes. These files are the ones the driver will communicate
  /// to the user/client as being objects of the selected compilation action.
  /// For example, a frontend job to compile a `.swift` source file may require multiple binary `inputs`,
  /// such as a pre-compiled bridging header and binary Swift module dependencies, but only the input `.swift`
  /// source file is meant to be the displayed object of compilation - a display input.
  public var displayInputs: [TypedVirtualPath]

  /// The primary inputs for compile jobs
  public var primaryInputs: [TypedVirtualPath]

  /// The outputs produced by the job.
  public var outputs: [TypedVirtualPath]

  /// Any extra environment variables which should be set while running the job.
  public var extraEnvironment: [String: String]

  /// Whether or not the job must be executed in place, replacing the current driver process.
  public var requiresInPlaceExecution: Bool

  /// The kind of job.
  public var kind: Kind

  /// A map from a primary input to all of its corresponding outputs
  private var compileInputOutputMap: [TypedVirtualPath : [TypedVirtualPath]]

  public init(
    moduleName: String,
    kind: Kind,
    tool: VirtualPath.Handle,
    commandLine: [ArgTemplate],
    displayInputs: [TypedVirtualPath]? = nil,
    inputs: [TypedVirtualPath],
    primaryInputs: [TypedVirtualPath],
    outputs: [TypedVirtualPath],
    inputOutputMap: [TypedVirtualPath : [TypedVirtualPath]] = [:],
    extraEnvironment: [String: String] = [:],
    requiresInPlaceExecution: Bool = false,
    supportsResponseFiles: Bool = false
  ) {
    self.moduleName = moduleName
    self.kind = kind
    self.tool = tool
    self.commandLine = commandLine
    self.displayInputs = displayInputs ?? []
    self.inputs = inputs
    self.primaryInputs = primaryInputs
    self.outputs = outputs
    self.compileInputOutputMap = inputOutputMap
    self.extraEnvironment = extraEnvironment
    self.requiresInPlaceExecution = requiresInPlaceExecution
    self.supportsResponseFiles = supportsResponseFiles
  }
}

extension Job {
  public enum InputError: Error, Equatable, DiagnosticData {
    case inputUnexpectedlyModified(TypedVirtualPath)

    public var description: String {
      switch self {
      case .inputUnexpectedlyModified(let input):
        return "input file '\(input.file.name)' was modified during the build"
      }
    }
  }

  public func verifyInputsNotModified(since recordedInputModificationDates: [TypedVirtualPath: Date], fileSystem: FileSystem) throws {
    for input in inputs {
      if let recordedModificationTime = recordedInputModificationDates[input],
         try fileSystem.lastModificationTime(for: input.file) != recordedModificationTime {
        throw InputError.inputUnexpectedlyModified(input)
      }
    }
  }
}

extension Job {
  // If the job's kind is `.compile`, serve a collection of Outputs corresponding
  // to a given primary input.
  public func getCompileInputOutputs(for input: TypedVirtualPath) -> [TypedVirtualPath]? {
    assert(self.kind == .compile)
    return compileInputOutputMap[input]
  }
}

extension Job : CustomStringConvertible {
  public var description: String {
    switch kind {
    case .compile:
        return "Compiling \(moduleName) \(displayInputs.first?.file.basename ?? "")"

    case .mergeModule:
        return "Merging module \(moduleName)"

    case .link:
        return "Linking \(moduleName)"

    case .generateDSYM:
        return "Generating dSYM for module \(moduleName)"

    case .autolinkExtract:
        return "Extracting autolink information for module \(moduleName)"

    case .emitModule:
        return "Emitting module for \(moduleName)"

    case .generatePCH:
        return "Compiling bridging header \(displayInputs.first?.file.basename ?? "")"

    case .moduleWrap:
      return "Wrapping Swift module \(moduleName)"

    case .generatePCM:
        return "Compiling Clang module \(moduleName)"

    case .interpret:
        return "Interpreting \(displayInputs.first?.file.name ?? "")"

    case .repl:
        return "Executing Swift REPL"

    case .verifyDebugInfo:
        return "Verifying debug information for module \(moduleName)"

    case .printTargetInfo:
        return "Gathering target information for module \(moduleName)"

    case .versionRequest:
        return "Getting Swift version information"

    case .help:
        return "Swift help"

    case .backend:
      return "Embedding bitcode for \(moduleName) \(displayInputs.first?.file.basename ?? "")"

    case .emitSupportedFeatures:
      return "Emitting supported Swift compiler features"

    case .scanDependencies:
      return "Scanning dependencies for module \(moduleName)"

    case .verifyModuleInterface:
      return "Verifying emitted module interface for module \(moduleName)"
    }
  }

  public var descriptionForLifecycle: String {
    switch kind {
    case .compile:
      return "Compiling \(inputsGeneratingCode.map {$0.file.basename}.joined(separator: ", "))"
    default:
      return description
    }
  }
}

extension Job.Kind {
  /// Whether this job kind uses the Swift frontend.
  public var isSwiftFrontend: Bool {
    switch self {
    case .backend, .compile, .mergeModule, .emitModule, .generatePCH,
        .generatePCM, .interpret, .repl, .printTargetInfo,
        .versionRequest, .emitSupportedFeatures, .scanDependencies, .verifyModuleInterface:
        return true

    case .autolinkExtract, .generateDSYM, .help, .link, .verifyDebugInfo, .moduleWrap:
        return false
    }
  }

  /// Whether this job kind is a compile job.
  public var isCompile: Bool {
    switch self {
    case .compile:
      return true
    case .backend, .mergeModule, .emitModule, .generatePCH,
         .generatePCM, .interpret, .repl, .printTargetInfo,
         .versionRequest, .autolinkExtract, .generateDSYM,
         .help, .link, .verifyDebugInfo, .scanDependencies,
         .emitSupportedFeatures, .moduleWrap, .verifyModuleInterface:
      return false
    }
  }
}
// MARK: - Job.ArgTemplate + Codable

extension Job.ArgTemplate: Codable {
  private enum CodingKeys: String, CodingKey {
    case flag, path, responseFilePath, joinedOptionAndPath, squashedArgumentList

    enum JoinedOptionAndPathCodingKeys: String, CodingKey {
      case option, path
    }

    enum SquashedArgumentListCodingKeys: String, CodingKey {
      case option, args
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case let .flag(a1):
      var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .flag)
      try unkeyedContainer.encode(a1)
    case let .pathHandle(a1):
      var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .path)
      try unkeyedContainer.encode(a1)
    case let .responseFilePathHandle(a1):
      var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .responseFilePath)
      try unkeyedContainer.encode(a1)
    case let .joinedOptionAndPathHandle(option, path):
      var keyedContainer = container.nestedContainer(
        keyedBy: CodingKeys.JoinedOptionAndPathCodingKeys.self,
        forKey: .joinedOptionAndPath)
      try keyedContainer.encode(option, forKey: .option)
      try keyedContainer.encode(path, forKey: .path)
    case .squashedArgumentList(option: let option, args: let args):
      var keyedContainer = container.nestedContainer(
        keyedBy: CodingKeys.SquashedArgumentListCodingKeys.self,
        forKey: .squashedArgumentList)
      try keyedContainer.encode(option, forKey: .option)
      try keyedContainer.encode(args, forKey: .args)
    }
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    guard let key = values.allKeys.first(where: values.contains) else {
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Did not find a matching key"))
    }
    switch key {
    case .flag:
      var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
      let a1 = try unkeyedValues.decode(String.self)
      self = .flag(a1)
    case .path:
      var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
      let a1 = try unkeyedValues.decode(VirtualPath.self)
      self = .path(a1)
    case .responseFilePath:
      var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
      let a1 = try unkeyedValues.decode(VirtualPath.self)
      self = .responseFilePath(a1)
    case .joinedOptionAndPath:
      let keyedValues = try values.nestedContainer(
        keyedBy: CodingKeys.JoinedOptionAndPathCodingKeys.self,
        forKey: .joinedOptionAndPath)
      self = .joinedOptionAndPathHandle(try keyedValues.decode(String.self, forKey: .option),
                                        try keyedValues.decode(VirtualPath.Handle.self, forKey: .path))
    case .squashedArgumentList:
      let keyedValues = try values.nestedContainer(
        keyedBy: CodingKeys.SquashedArgumentListCodingKeys.self,
        forKey: .squashedArgumentList)
      self = .squashedArgumentList(option: try keyedValues.decode(String.self, forKey: .option),
                                   args: try keyedValues.decode([Job.ArgTemplate].self, forKey: .args))
    }
  }
}
