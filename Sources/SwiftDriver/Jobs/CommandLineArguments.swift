//===--- CommandLineArguments.swift - Command Line Argument Manipulation --===//
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

/// Utilities for manipulating a list of command line arguments, including
/// constructing one from a set of ParsedOptions.
extension Array where Element == Job.ArgTemplate {
  /// Append a fixed flag to the command line arguments.
  ///
  /// When possible, use the more semantic forms `appendFlag` or
  /// `append(_: Option)`.
  mutating func appendFlag<StringType: StringProtocol>(_ string: StringType) {
    append(.flag(String(string)))
  }

  /// Append multiple flags to the command line arguments.
  ///
  /// When possible, use the more semantic forms `appendFlag` or
  /// `append(_: Option)`.
  mutating func appendFlags(_ flags: String...) {
    appendFlags(flags)
  }

  /// Append multiple flags to the command line arguments.
  ///
  /// When possible, use the more semantic forms `appendFlag` or
  /// `append(_: Option)`.
  mutating func appendFlags(_ flags: [String]) {
    for flag in flags {
      append(.flag(flag))
    }
  }

  /// Append a virtual path to the command line arguments.
  mutating func appendPath(_ path: VirtualPath) {
    append(.path(path))
  }

  /// Append an absolute path to the command line arguments.
  mutating func appendPath(_ path: AbsolutePath) {
    append(.path(.absolute(path)))
  }

  /// Append an option's spelling to the command line arguments.
  mutating func appendFlag(_ option: Option) {
    switch option.kind {
    case .flag, .joinedOrSeparate, .remaining, .separate:
      break
    case .commaJoined, .input, .joined:
      fatalError("Option cannot be appended as a flag: \(option)")
    }

    append(.flag(option.spelling))
  }

  /// Append a single argument from the given option.
  private mutating func appendSingleArgument(option: Option, argument: String) throws {
    if option.attributes.contains(.argumentIsPath) {
      append(.path(try VirtualPath(path: argument)))
    } else {
      appendFlag(argument)
    }
  }

  /// Append a parsed option to the array of argument templates, expanding
  /// until multiple arguments if required.
  mutating func append(_ parsedOption: ParsedOption) throws {
    let option = parsedOption.option
    let argument = parsedOption.argument

    switch option.kind {
    case .input:
      try appendSingleArgument(option: option, argument: argument.asSingle)

    case .flag:
      appendFlag(option)

    case .separate, .joinedOrSeparate:
      appendFlag(option.spelling)
      try appendSingleArgument(option: option, argument: argument.asSingle)

    case .commaJoined:
      assert(!option.attributes.contains(.argumentIsPath))
      appendFlag(option.spelling + argument.asMultiple.joined(separator: ","))

    case .remaining:
      appendFlag(option.spelling)
      for arg in argument.asMultiple {
        try appendSingleArgument(option: option, argument: arg)
      }

    case .joined:
      if option.attributes.contains(.argumentIsPath) {
        append(.joinedOptionAndPath(option.spelling, try VirtualPath(path: argument.asSingle)))
      } else {
        appendFlag(option.spelling + argument.asSingle)
      }
    }
  }

  /// Append the last parsed option that matches one of the given options
  /// to this command line.
  mutating func appendLast(_ options: Option..., from parsedOptions: inout ParsedOptions) throws {
    guard let parsedOption = parsedOptions.last(for: options) else {
      return
    }

    try append(parsedOption)
  }

  /// Append the last parsed option from the given group to this command line.
  mutating func appendLast(in group: Option.Group, from parsedOptions: inout ParsedOptions) throws {
    guard let parsedOption = parsedOptions.getLast(in: group) else {
      return
    }

    try append(parsedOption)
  }

  mutating func append(contentsOf options: [ParsedOption]) throws {
    for option in options {
      try append(option)
    }
  }

  /// Append all parsed options that match one of the given options
  /// to this command line.
  mutating func appendAll(_ options: Option..., from parsedOptions: inout ParsedOptions) throws {
    for matching in parsedOptions.arguments(for: options) {
      try append(matching)
    }
  }

  /// Append just the arguments from all parsed options that match one of the given options
  /// to this command line.
  mutating func appendAllArguments(_ options: Option..., from parsedOptions: inout ParsedOptions) throws {
    for matching in parsedOptions.arguments(for: options) {
      try self.appendSingleArgument(option: matching.option, argument: matching.argument.asSingle)
    }
  }

  /// Append the last of the given flags that appears in the parsed options,
  /// or the flag that corresponds to the default value if neither
  /// appears.
  mutating func appendFlag(true trueFlag: Option, false falseFlag: Option, default defaultValue: Bool, from parsedOptions: inout ParsedOptions) {
    let isTrue = parsedOptions.hasFlag(
      positive: trueFlag,
      negative: falseFlag,
      default: defaultValue
    )
    appendFlag(isTrue ? trueFlag : falseFlag)
  }

  @available(*, deprecated, renamed: "joinedUnresolvedArguments")
  public var joinedArguments: String { joinedUnresolvedArguments }

  /// A shell-escaped string representation of the arguments, as they would appear on the command line.
  /// Note: does not resolve arguments.
  public var joinedUnresolvedArguments: String {
    return self.map {
      switch $0 {
      case .flag(let string):
        return string.spm_shellEscaped()
      case .path(let path):
        return path.name.spm_shellEscaped()
      case .responseFilePath(let path):
        return "@\(path.name.spm_shellEscaped())"
      case let .joinedOptionAndPath(option, path):
        return option.spm_shellEscaped() + path.name.spm_shellEscaped()
      case let .squashedArgumentList(option, args):
        return (option + args.joinedUnresolvedArguments).spm_shellEscaped()
      }
    }.joined(separator: " ")
  }
}
