//===--------------- FileList.swift - File list model ---------------------===//
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

import Foundation

public enum FileList: Hashable {
  /// File of file paths
  case list([VirtualPath.Handle])
  /// YAML OutputFileMap
  case outputFileMap(OutputFileMap)
}

extension FileList: Codable {
  private enum Key: String, Codable {
    case list
    case outputFileMap
  }

  public init(from decoder: Decoder) throws {
    var container = try decoder.unkeyedContainer()
    let key = try container.decode(Key.self)
    switch key {
    case .list:
      let contents = try container.decode([VirtualPath.Handle].self)
      self = .list(contents)
    case .outputFileMap:
      let map = try container.decode(OutputFileMap.self)
      self = .outputFileMap( map)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.unkeyedContainer()
    switch self {
    case let .list(contents):
      try container.encode(Key.list)
      try container.encode(contents)
    case let .outputFileMap(map):
      try container.encode(Key.outputFileMap)
      try container.encode(map)
    }
  }
}
