//===--------------- ParsedOptions.swift - Swift Parsed Options -----------===//
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

/// Describes a single parsed option with its argument (if any).
public struct ParsedOption {
  public enum Argument {
    case none
    case single(String)
    case multiple([String])

    /// Retrieve the single-string argument.
    public var asSingle: String {
      switch self {
      case .single(let result):
        return result

      default:
        fatalError("not a single argument")
      }
    }

    /// Retrieve multiple string arguments.
    public var asMultiple: [String] {
      switch self {
      case .multiple(let result):
        return result

      default:
        fatalError("not a multiple argument")
      }
    }
  }

  /// The option that was parsed.
  public let option: Option

  /// The argument bound to this option.
  public let argument: Argument

  /// The index in the command line where this argument appeared.
  public let index: Int

  public init(option: Option, argument: Argument, index: Int) {
    self.option = option
    self.argument = argument
    self.index = index
  }
}

extension ParsedOption: CustomStringConvertible {
  public var description: String {
    switch option.kind {
    case .input:
      return argument.asSingle.spm_shellEscaped()

    case .commaJoined:
      return (option.spelling + argument.asMultiple.joined(separator: ",")).spm_shellEscaped()

    case .flag:
      return option.spelling

    case .joined:
      return (option.spelling + argument.asSingle).spm_shellEscaped()

    case .joinedOrSeparate, .separate:
      return option.spelling + " " + argument.asSingle.spm_shellEscaped()

    case .remaining:
      let args = argument.asMultiple
      if args.isEmpty {
        return option.spelling
      }
      return option.spelling + " " + argument.asMultiple.map { $0.spm_shellEscaped() }.joined(separator: " ")
    }
  }
}

/// Capture a list of command-line arguments that have been parsed
/// into a list of options with their arguments.
public struct ParsedOptions {
  public typealias Argument = ParsedOption.Argument

  /// The parsed options, which match up an option with its argument(s).
  public var parsedOptions: [ParsedOption] = []

  /// Maps the canonical spelling of an option to all the instances of
  /// that option that we've seen in the map, and their index in the
  /// parsedOptions array. Prefer to use this for lookup
  /// whenever you can.
  private var optionIndex = [String: [ParsedOption]]()

  /// Maps option groups to the set of parsed options that are present for
  /// them.
  private var groupIndex = [Option.Group: [ParsedOption]]()

  /// Indication of which of the parsed options have been "consumed" by the
  /// driver. Any unconsumed options could have been omitted from the command
  /// line.
  private var consumed: [Bool] = []

  /// Delay unknown flags throwing because some of them may be recognized as
  /// swift-frontend flags.
  private var unknownFlags: [OptionParseError] = []
}

extension ParsedOptions {
  mutating func addUnknownFlag(index: Int, argument: String) {
    unknownFlags.append(OptionParseError.unknownOption(index: index, argument: argument))
  }
  public func saveUnknownFlags(isSupported: (String) -> Bool) throws -> [String] {
    var savedUnknownFlags: [String] = []
    try unknownFlags.forEach {
      switch $0 {
      case .unknownOption(index: _, argument: let argument):
        if isSupported(argument) {
          savedUnknownFlags.append(argument)
          break
        }
        if argument == "-unlikely-flag-for-testing" {
          savedUnknownFlags.append(argument)
          break
        }
        throw $0
      default:
        throw $0
      }
    }
    return savedUnknownFlags
  }
}

public extension ParsedOptions {
  internal mutating func buildIndex() {
    optionIndex.removeAll()
    for parsed in parsedOptions {
      optionIndex[parsed.option.canonical.spelling, default: []].append(parsed)
      if let group = parsed.option.group {
        groupIndex[group, default: []].append(parsed)
      }
    }
  }

  mutating func addOption(_ option: Option, argument: Argument) {
    let parsed = ParsedOption(
      option: option,
      argument: argument,
      index: parsedOptions.count
    )
    parsedOptions.append(parsed)
    consumed.append(false)
  }

  mutating func addInput(_ input: String) {
    addOption(.INPUT, argument: .single(input))
  }
}

extension ParsedOptions: CustomStringConvertible {
  /// Pretty-printed version of all of the parsed options.
  public var description: String {
    return parsedOptions.map { $0.description }.joined(separator: " ")
  }
}

extension ParsedOptions {
  /// Produce "raw" command-line arguments from the parsed options.
  public var commandLine: [String] {
    var result: [String] = []
    for parsed in parsedOptions {
      switch parsed.option.kind {
      case .input:
        result.append(parsed.argument.asSingle)

      case .commaJoined:
        result.append(parsed.option.spelling + parsed.argument.asMultiple.joined(separator: ","))

      case .flag:
        result.append(parsed.option.spelling)

      case .joined:
        result.append(parsed.option.spelling + parsed.argument.asSingle)

      case .joinedOrSeparate, .separate:
        result.append(parsed.option.spelling)
        result.append(parsed.argument.asSingle)

      case .remaining:
        result.append(parsed.option.spelling)
        result.append(contentsOf: parsed.argument.asMultiple)
      }
    }
    return result
  }
}

/// Access to the various options that have been parsed.
extension ParsedOptions {
  /// Return all options that match the given predicate.
  ///
  /// Any options that match the `isIncluded` predicate will be marked "consumed".
  public mutating func filter(where isIncluded: (ParsedOption) throws -> Bool) rethrows -> [ParsedOption] {
    var result: [ParsedOption] = []
    for option in parsedOptions {
      if try isIncluded(option) {
        consumed[option.index] = true
        result.append(option)
      }
    }

    return result
  }

  public mutating func arguments(for options: Option...) -> [ParsedOption] {
    return arguments(for: options)
  }

  public mutating func arguments(for options: [Option]) -> [ParsedOption] {
    // The relative ordering of different options is sometimes significant, so
    // sort the results by their position in the command line.
    return options.flatMap { lookup($0) }.sorted { $0.index < $1.index }
  }

  public mutating func arguments(in group: Option.Group) -> [ParsedOption] {
    return groupIndex[group, default: []]
  }

  public mutating func last(for options: Option...) -> ParsedOption? {
    return last(for: options)
  }

  public mutating func last(for options: [Option]) -> ParsedOption? {
    return arguments(for: options).last
  }

  /// Return the last parsed options that matches the given predicate.
  ///
  /// Any options that match the `isIncluded` predicate will be marked "consumed".
  public mutating func last(where isIncluded: (ParsedOption) throws -> Bool) rethrows -> ParsedOption? {
    return try filter(where: isIncluded).last
  }

  /// Does this contain a particular option.
  public mutating func contains(_ option: Option) -> Bool {
    assert(option.alias == nil, "Don't check for aliased options")
    return !lookup(option).isEmpty
  }

  /// Determine whether the parsed options contains an option in the given
  /// group.
  public mutating func contains(in group: Option.Group) -> Bool {
    return getLast(in: group) != nil
  }

  /// Does this contain any inputs?
  ///
  /// This operation does not consume any inputs.
  public var hasAnyInput: Bool {
    return !lookupWithoutConsuming(.INPUT).isEmpty || !lookupWithoutConsuming(.e).isEmpty
  }

  /// Walk through all of the parsed options, modifying each one.
  ///
  /// This operation does not consume any options.
  public mutating func forEachModifying(body: (inout ParsedOption) throws -> Void) rethrows {
    for index in parsedOptions.indices {
      try body(&parsedOptions[index])
    }
    buildIndex()
  }

  internal func lookupWithoutConsuming(_ option: Option) -> [ParsedOption] {
    optionIndex[option.canonical.spelling, default: []]
  }

  internal mutating func lookup(_ option: Option) -> [ParsedOption] {
    let opts = lookupWithoutConsuming(option)
    for opt in opts {
      consumed[opt.index] = true
    }
    return opts
  }

  /// Find all of the inputs.
  public var allInputs: [String] {
    mutating get {
      lookup(.INPUT).map { $0.argument.asSingle }
    }
  }

  /// Determine whether the parsed options contain an argument with one of
  /// the given options
  public func hasArgument(_ options: Option...) -> Bool {
    return options.contains { !lookupWithoutConsuming($0).isEmpty }
  }

  /// Given an option and its negative form, return
  /// true if the option is present, false if the negation is present, and
  /// `default` if neither option is given. If both the option and its
  /// negation are present, the last one wins.
  public mutating func hasFlag(positive: Option,
                               negative: Option,
                               default: Bool) -> Bool {
    let positiveOpt = lookup(positive).last
    let negativeOpt = lookup(negative).last

    // If neither are present, return the default
    guard positiveOpt != nil || negativeOpt != nil else {
      return `default`
    }

    // If the positive isn't provided, then the negative will be
    guard let positive = positiveOpt else { return false }

    // If the negative isn't provided, then the positive will be
    guard let negative = negativeOpt else { return true }

    // Otherwise, return true if the positive index is greater than the negative,
    // false otherwise
    return positive.index > negative.index
  }

  /// Get the last argument matching the given option.
  public mutating func getLastArgument(_ option: Option) -> Argument? {
    assert(option.alias == nil, "Don't check for aliased options")
    return lookup(option).last?.argument
  }

  /// Get the last parsed option within the given option group.
  /// FIXME: Should mark the gotten option as "used". That's why must be `mutating`
  public mutating func getLast(in group: Option.Group) -> ParsedOption? {
    return groupIndex[group]?.last
  }

  /// Remove argument from parsed options.
  public mutating func eraseArgument(_ option: Option) {
    parsedOptions.removeAll { $0.option == option }
    optionIndex.removeValue(forKey: option.spelling)
    if let group = option.group {
      groupIndex[group]?.removeAll { $0.option == option }
    }
  }

  /// Remove all arguments of a given group from parsed options.
  public mutating func eraseAllArguments(in group: Option.Group) {
    for parsedOption in parsedOptions {
      if parsedOption.option.group == group {
        eraseArgument(parsedOption.option)
      }
    }
  }

  /// Remove all arguments with a .supplementaryOutput attribute
  public mutating func eraseSupplementaryOutputs() {
    for parsedOption in parsedOptions {
      if parsedOption.option.attributes.contains(.supplementaryOutput) {
        eraseArgument(parsedOption.option)
      }
    }
  }

  public var unconsumedOptions: [ParsedOption] {
    zip(parsedOptions, consumed).filter { !$0.1 }.map(\.0)
  }
}
