//===-------------- NameableByRawValue.swift - Swift Testing --------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// String raw values are used as names for source files and modules.
/// (See `TestProtocol`.)
protocol NameableByRawValue: RawRepresentable where RawValue == String {
}

extension NameableByRawValue {
  var name: String {rawValue}
}
