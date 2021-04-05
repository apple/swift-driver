//===--------------- BuildRecord.swift - Swift Input File Info Map -------===//
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
@_implementationOnly import Yams

/// Holds the info about inputs needed to plan incremenal compilation
/// A.k.a. BuildRecord was the legacy name
public struct BuildRecord {
  public let swiftVersion: String
  /// When testing, the argsHash may be missing from the build record
  public let argsHash: String?
  public let buildTime: Date
  /// The date is the modification time of the main input file the last time the driver ran
  public let inputInfos: [VirtualPath.Handle: InputInfo]

  public init(argsHash: String?,
              swiftVersion: String,
              buildTime: Date,
              inputInfos: [VirtualPath.Handle: InputInfo]) {
    self.argsHash = argsHash
    self.swiftVersion = swiftVersion
    self.buildTime = buildTime
    self.inputInfos = inputInfos
  }

  private enum SectionName: String, CaseIterable {
    case swiftVersion = "version"
    case argsHash = "options"
    case buildTime = "build_time"
    case inputInfos = "inputs"

    var serializedName: String { rawValue }
  }

  var allInputs: Set<VirtualPath.Handle> {
    Set(inputInfos.map { $0.key })
  }
}

// MARK: - Reading the old map and deciding whether to use it
public extension BuildRecord {
  init?(contents: String, failedToReadOutOfDateMap: (String?) -> Void) {
    guard let sections = try? Parser(yaml: contents, resolver: .basic, encoding: .utf8)
            .singleRoot()?.mapping
    else {
      failedToReadOutOfDateMap(nil)
      return nil
    }
    var argsHash: String?
    var swiftVersion: String?
    // Legacy driver does not disable incremental if no buildTime field.
    var buildTime: Date = .distantPast
    var inputInfos: [VirtualPath.Handle: InputInfo]?
    for (key, value) in sections {
      guard let k = key.string else {
        failedToReadOutOfDateMap(nil)
        return nil
      }
      switch k {
      case SectionName.swiftVersion.serializedName:
        // There's a test that uses "" for an illegal value
        guard let s = value.string, s != "" else {
          failedToReadOutOfDateMap("Malformed value for key '\(k)'")
          return nil
        }
        swiftVersion = s
      case SectionName.argsHash.serializedName:
        guard let s = value.string, s != "" else {
          failedToReadOutOfDateMap("no name node in build record")
          return nil
        }
        argsHash = s
     case SectionName.buildTime.serializedName:
      guard let d = Self.decodeDate(value,
                                    forInputInfo: false,
                                    failedToReadOutOfDateMap)
      else {
        return nil
      }
      buildTime = d
      case SectionName.inputInfos.serializedName:
        guard let ii = Self.decodeInputInfos(value, failedToReadOutOfDateMap) else {
          return nil
        }
        inputInfos = ii
      default:
        failedToReadOutOfDateMap("Unexpected key '\(k)'")
        return nil
      }
    }
    // The legacy driver allows argHash to be absent to ease testing.
    // Mimic the legacy driver for testing ease: If no `argsHash` section,
    // record still matches.
    guard let sv = swiftVersion else {
      failedToReadOutOfDateMap("Malformed value for key '\(SectionName.swiftVersion.serializedName)'")
      return nil
    }
    guard let iis = inputInfos else {
      failedToReadOutOfDateMap("Malformed value for key '\(SectionName.inputInfos.serializedName)'")
      return nil
    }
    self.init(argsHash: argsHash,
              swiftVersion: sv,
              buildTime: buildTime,
              inputInfos: iis)
  }

  private static func decodeDate(
    _ node: Yams.Node,
    forInputInfo: Bool,
    _ failedToReadOutOfDateMap: (String) -> Void
  ) -> Date? {
    guard let vals = node.sequence else {
      failedToReadOutOfDateMap(
        forInputInfo
          ? "no sequence node for input entry in build record"
          : "could not read time value in build record")
      return nil
    }
    guard vals.count == 2,
          let secs = vals[0].int,
          let ns = vals[1].int
    else {
      failedToReadOutOfDateMap("could not read time value in build record")
      return nil
    }
    return Date(legacyDriverSecs: secs, nanos: ns)
  }

  private static func decodeInputInfos(
    _ node: Yams.Node,
    _ failedToReadOutOfDateMap: (String) -> Void
  ) -> [VirtualPath.Handle: InputInfo]? {
    guard let map = node.mapping else {
      failedToReadOutOfDateMap(
        "Malformed value for key '\(SectionName.inputInfos.serializedName)'")
      return nil
    }
  var infos = [VirtualPath.Handle: InputInfo]()
    for (keyNode, valueNode) in map {
      guard let pathString = keyNode.string,
            let path = try? VirtualPath.intern(path: pathString)
      else {
        failedToReadOutOfDateMap("no input entry in build record")
        return nil
      }
      guard let previousModTime = decodeDate(valueNode,
                                             forInputInfo: true,
                                             failedToReadOutOfDateMap)
      else {
        return nil
      }
      guard let inputInfo = InputInfo(tag: valueNode.tag.description,
                                      previousModTime: previousModTime,
                                      failedToReadOutOfDateMap: failedToReadOutOfDateMap)
      else {
        return nil
      }
      infos[path] = inputInfo
    }
    return infos
   }
}

// MARK: - Creating and writing a new map
extension BuildRecord {
  /// Create a new buildRecord for writing
  init(jobs: [Job],
       finishedJobResults: [BuildRecordInfo.JobResult],
       skippedInputs: Set<TypedVirtualPath>?,
       compilationInputModificationDates: [TypedVirtualPath: Date],
       actualSwiftVersion: String,
       argsHash: String!,
       timeBeforeFirstJob: Date
  ) {
    let jobResultsByInput = Dictionary(uniqueKeysWithValues:
      finishedJobResults.flatMap { entry in
        entry.job.inputsGeneratingCode.map { ($0, entry.result) }
    })
    let inputInfosArray = compilationInputModificationDates
      .map { input, modDate -> (VirtualPath.Handle, InputInfo) in
        let status = InputInfo.Status(wasSkipped: skippedInputs?.contains(input),
                                      jobResult: jobResultsByInput[input])
        return (input.fileHandle, InputInfo(status: status, previousModTime: modDate))
      }

    self.init(
      argsHash: argsHash,
      swiftVersion: actualSwiftVersion,
      buildTime: timeBeforeFirstJob,
      inputInfos: Dictionary(uniqueKeysWithValues: inputInfosArray)
    )
  }

  /// Pass in `currentArgsHash` to ensure it is non-nil
  /*@_spi(Testing)*/ public func encode(currentArgsHash: String,
                                        diagnosticEngine: DiagnosticsEngine
  ) -> String? {
      let pathsAndInfos = inputInfos.map {
        input, inputInfo -> (String, InputInfo) in
        return (VirtualPath.lookup(input).name, inputInfo)
      }
      let inputInfosNode = Yams.Node(
        pathsAndInfos
          .sorted {$0.0 < $1.0}
          .map {(Yams.Node($0.0, .implicit, .doubleQuoted), Self.encode($0.1))}
      )
    let fieldNodes = [
      (SectionName.swiftVersion, Yams.Node(swiftVersion,    .implicit, .doubleQuoted)),
      (SectionName.argsHash,     Yams.Node(currentArgsHash, .implicit, .doubleQuoted)),
      (SectionName.buildTime,    Self.encode(buildTime)),
      (SectionName.inputInfos,   inputInfosNode )
      ] .map { (Yams.Node($0.0.serializedName), $0.1) }

    let buildRecordNode = Yams.Node(fieldNodes, .implicit, .block)
   // let options = Yams.Emitter.Options(canonical: true)
    do {
      return try Yams.serialize(node: buildRecordNode,
                                width: -1,
                                sortKeys: false)
    } catch {
      diagnosticEngine.emit(.warning_could_not_serialize_build_record(error))
      return nil
    }
  }

  private static func encode(_ date: Date, tag tagString: String? = nil) -> Yams.Node {
    let secsAndNanos = date.legacyDriverSecsAndNanos
    return Yams.Node(
      secsAndNanos.map {Yams.Node(String($0))},
      tagString.map {Yams.Tag(Yams.Tag.Name(rawValue: $0))} ?? .implicit,
      .flow)
  }

  private static func encode(_ inputInfo: InputInfo) -> Yams.Node {
    encode(inputInfo.previousModTime, tag: inputInfo.tag)
  }

}

extension Diagnostic.Message {
  static func warning_could_not_serialize_build_record(_ err: Error
  ) -> Diagnostic.Message {
    .warning("next compile won't be incremental; Could not serialize build record: \(err.localizedDescription)")
  }
  static func warning_could_not_write_build_record_not_absolutePath(
    _ path: VirtualPath
  ) -> Diagnostic.Message {
    .warning("next compile won't be incremental; build record path was not absolute: \(path)")
  }
  static func warning_could_not_write_build_record(_ path: AbsolutePath
  ) -> Diagnostic.Message {
    .warning("next compile won't be incremental; could not write build record to \(path)")
  }
}
