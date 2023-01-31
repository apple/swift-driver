//===------------- main.swift - Swift Explain Main Entrypoint ------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SwiftOptions
import SwiftDriver
#if os(Windows)
import CRT
#elseif os(iOS) || os(macOS) || os(tvOS) || os(watchOS)
import Darwin
#else
import Glibc
#endif
import var TSCBasic.localFileSystem
import class TSCBasic.DiagnosticsEngine

let diagnosticsEngine = DiagnosticsEngine(handlers: [Driver.stderrDiagnosticsHandler])

func isToolPath(_ optionalString: String?) -> Bool {
  guard let string = optionalString else { return false }
  // ugh
  return string.hasSuffix("swift-frontend") ||
         string.hasSuffix("swiftc") ||
         string.hasSuffix("clang") ||
         string.hasSuffix("libtool") ||
         string.hasSuffix("dsymutil") ||
         string.hasSuffix("clang") ||
         string.hasSuffix("clang++") ||
         string.hasSuffix("swift-autolink-extract") ||
         string.hasSuffix("lldb") ||
         string.hasSuffix("dwarfdump") ||
         string.hasSuffix("swift-help") ||
         string.hasSuffix("swift-api-digester")
}

func printCommandIntro(firstArg: String? = nil) {
  print("")
  print("-- Explained command-line:")
}

// Partition all the arguments into potentially multiple commands
// starting with a path to an executable tool.
func partitionCommandLineIntoToolInvocations(_ args: [String]) -> [[String]] {
  var commandLines: [[String]] = []
  var currentCommandLine: [String] = []
  for arg in args {
    if isToolPath(arg) {
      if !currentCommandLine.isEmpty {
        commandLines.append(currentCommandLine)
      }
      currentCommandLine = [arg]
      continue
    }
    currentCommandLine.append(arg)
  }
  commandLines.append(currentCommandLine)
  return commandLines
}

do {
  var args = CommandLine.arguments
  guard args.count > 1 else {
    exit(0)
  }
  args.removeFirst() // Path to swift-explain itself

  let commandLines = partitionCommandLineIntoToolInvocations(args)
  for commandLine in commandLines {
    guard !commandLine.isEmpty else {
      continue
    }
    // Print the intro and the path to the tool executable
    printCommandIntro(firstArg: commandLine.first)
    let arguments: [String]
    if isToolPath(commandLine.first) {
      print(commandLine[0])
      arguments = Array(commandLine[1...])
    } else {
      arguments = commandLine
    }

    // Expand and parse the arguments
    let expandedArgs =
      try Driver.expandResponseFiles(Array(arguments),
                                     fileSystem: localFileSystem,
                                     diagnosticsEngine: diagnosticsEngine)
    let optionTable = OptionTable()
    let parsedOptions = try optionTable.parse(Array(expandedArgs),
                                              for: .batch,
                                              delayThrows: true,
                                              includeNoDriver: true)
    for opt in parsedOptions.parsedOptions {
      switch opt.option.kind {
      case .input:
        let path = try VirtualPath(path: opt.description)
        print(opt.description, terminator: "")
        var padding = 80-opt.description.count
        if padding < 0 {
          padding = 0
        }
        print(String(repeating: " ", count: padding), terminator: "")
        print(" # Input", terminator: "")
        if let fileExtension = path.extension {
          print(" (\(fileExtension.description))")
        } else {
          print()
        }
      default:
        print(opt.description, terminator: "")
        var padding = 80-opt.description.count
        if padding < 0 {
          padding = 0
        }
        print(String(repeating: " ", count: padding), terminator: "")
        let helpText = opt.option.helpText ?? opt.option.alias?.helpText ?? "UNKNOWN"
        print(" # \(helpText)")
      }
    }
    print("")
  }
} catch {
  print("error: \(error)")
  exit(1)
}
