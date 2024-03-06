//===--------------- OptionParsing.swift - Swift Option Parser ------------===//
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

import protocol TSCBasic.DiagnosticData

public enum OptionParseError : Error, Equatable, DiagnosticData {
  case unknownOption(index: Int, argument: String)
  case missingArgument(index: Int, argument: String)
  case unsupportedOption(index: Int, argument: String, option: Option, currentDriverKind: DriverKind)

  public var description: String {
    switch self {
    case let .unknownOption(index: _, argument: arg):
      return "unknown argument: '\(arg)'"
    case let .missingArgument(index: _, argument: arg):
      return "missing argument value for '\(arg)'"
    case let .unsupportedOption(index: _, argument: arg, option: option, currentDriverKind: driverKind):
      // TODO: This logic to choose the recommended kind is copied from the C++
      // driver and could be improved.
      let recommendedDriverKind: DriverKind = option.attributes.contains(.noBatch) ? .interactive : .batch
      return "option '\(arg)' is not supported by '\(driverKind.usage)'; did you mean to use '\(recommendedDriverKind.usage)'?"
    }
  }
}

extension OptionTable {
  /// Parse the given command-line arguments into a set of options.
  ///
  /// Throws an error if the command line contains any errors.
  public func parse(_ arguments: [String],
                    for driverKind: DriverKind,
                    delayThrows: Bool = false,
                    includeNoDriver: Bool = false) throws -> ParsedOptions {
    var trie = PrefixTrie<Option>()
    // Add all options, ignoring the .noDriver ones
    for opt in options {
      if opt.attributes.contains(.noDriver) {
        if includeNoDriver {
          trie[opt.spelling] = opt
        }
      } else {
        trie[opt.spelling] = opt
      }
    }

    var parsedOptions = ParsedOptions()
    var seenDashE = false
    var index = arguments.startIndex
    while index < arguments.endIndex {
      // Capture the next argument.
      let argument = arguments[index]
      index += 1

      // Ignore empty arguments.
      if argument.isEmpty {
        continue
      }

      // If this is not a flag, record it as an input.
      if argument == "-" || argument.first! != "-" {
        // If we've seen -e, this argument and all remaining ones are arguments to the -e script.
        if driverKind == .interactive && seenDashE {
          parsedOptions.addOption(.DASHDASH, argument: .multiple(Array(arguments[(index-1)...])))
          break
        }

        parsedOptions.addInput(argument)

        // In interactive mode, synthesize a "--" argument for all args after the first input.
        if driverKind == .interactive && index < arguments.endIndex {
          parsedOptions.addOption(.DASHDASH, argument: .multiple(Array(arguments[index...])))
          break
        }

        continue
      }

      // Match to an option, identified by key. Note that this is a prefix
      // match -- if the option is a `.flag`, we'll explicitly check to see if
      // there's an unmatched suffix at the end, and pop an error. Otherwise,
      // we'll treat the unmatched suffix as the argument to the option.
      guard let option = trie[argument] else {
        if delayThrows {
          parsedOptions.addUnknownFlag(index: index - 1, argument: argument)
          continue
        } else {
          throw OptionParseError.unknownOption(index: index - 1, argument: argument)
        }
      }

      let verifyOptionIsAcceptedByDriverKind = {
        // Make sure this option is supported by the current driver kind.
        guard option.isAccepted(by: driverKind) ||
                (option.attributes.contains(.noDriver) && includeNoDriver) else {
          throw OptionParseError.unsupportedOption(
            index: index - 1, argument: argument, option: option,
            currentDriverKind: driverKind)
        }
      }

      if option == .e {
        seenDashE = true
      }

      // Translate the argument
      switch option.kind {
      case .input:
        parsedOptions.addOption(option, argument: .single(argument))

      case .commaJoined:
        // Comma-separated list of arguments follows the option spelling.
        try verifyOptionIsAcceptedByDriverKind()
        let rest = argument.dropFirst(option.spelling.count)
        parsedOptions.addOption(
          option,
          argument: .multiple(rest.split(separator: ",").map { String($0) }))

      case .flag:
        // Make sure there was no extra text.
        if argument != option.spelling {
          throw OptionParseError.unknownOption(
            index: index - 1, argument: argument)
        }
        try verifyOptionIsAcceptedByDriverKind()
        parsedOptions.addOption(option, argument: .none)

      case .joined:
        // Argument text follows the option spelling.
        try verifyOptionIsAcceptedByDriverKind()
        parsedOptions.addOption(
          option,
          argument: .single(String(argument.dropFirst(option.spelling.count))))

      case .joinedOrSeparate:
        // Argument text follows the option spelling.
        try verifyOptionIsAcceptedByDriverKind()
        let arg = argument.dropFirst(option.spelling.count)
        if !arg.isEmpty {
          parsedOptions.addOption(option, argument: .single(String(arg)))
          break
        }

        if index == arguments.endIndex {
          throw OptionParseError.missingArgument(
            index: index - 1, argument: argument)
        }

        parsedOptions.addOption(option, argument: .single(arguments[index]))
        index += 1

      case .remaining:
        if argument != option.spelling {
          throw OptionParseError.unknownOption(
            index: index - 1, argument: argument)
        }
        parsedOptions.addOption(.DASHDASH, argument: .multiple(Array()))
        arguments[index...].map { String($0) }.forEach { parsedOptions.addInput($0) }
        index = arguments.endIndex

      case .separate:
        if argument != option.spelling {
          throw OptionParseError.unknownOption(
            index: index - 1, argument: argument)
        }
        try verifyOptionIsAcceptedByDriverKind()

        if index == arguments.endIndex {
          throw OptionParseError.missingArgument(
            index: index - 1, argument: argument)
        }

        parsedOptions.addOption(option, argument: .single(arguments[index]))
        index += 1
      }
    }
    parsedOptions.buildIndex()
    return parsedOptions
  }
}
