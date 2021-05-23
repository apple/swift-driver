//===--------------- DOTJobGraphSerializer.swift - Swift GraphViz ---------===//
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

/// Serializes the job graph to a .dot file
@_spi(Testing) public struct DOTJobGraphSerializer {
  var kindCounter = [Job.Kind: Int]()
  var hasEmittedStyling = Set<String>()
  let jobs: [Job]
  let toolchain: Toolchain

  /// Creates a serializer that will serialize the given set of top level jobs.
  public init(jobs: [Job], toolchain: Toolchain) {
    self.jobs = jobs
    self.toolchain = toolchain
  }

  /// Gets a unique label for a job name
  mutating func label(for job: Job) throws -> String {
    var label = "\(job.kind)"
    if let count = kindCounter[job.kind] {
      label += " \(count)"
    }
    label += " (\(try toolchain.getToolPath(job.tool).basename))"
    kindCounter[job.kind, default: 0] += 1
    return label
  }

  /// Quote the name and escape the quotes
  func quoteName(_ name: String) -> String {
    return "\"" + name.replacingOccurrences(of: "\"", with: "\\\"") + "\""
  }

  public mutating func writeDOT<Stream: TextOutputStream>(to stream: inout Stream) throws {
    stream.write("digraph Jobs {\n")
    for job in jobs {
      let jobName = quoteName(try label(for: job))
      if !hasEmittedStyling.contains(jobName) {
        stream.write("  \(jobName) [style=bold];\n")
      }
      for input in job.inputs {
        let inputName = quoteName(input.file.name)
        if hasEmittedStyling.insert(inputName).inserted {
          stream.write("  \(inputName) [fontsize=12];\n")
        }
        stream.write("  \(inputName) -> \(jobName) [color=blue];\n")
      }
      for output in job.outputs {
        let outputName = quoteName(output.file.name)
        if hasEmittedStyling.insert(outputName).inserted {
          stream.write("  \(outputName) [fontsize=12];\n")
        }
        stream.write("  \(jobName) -> \(outputName) [color=green];\n")
      }
    }
    stream.write("}\n")
  }
}
