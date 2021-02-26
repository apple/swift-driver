//===------------------ DirectAndTransitiveCollections.swift --------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

// Use the type system to ensure that dependencies are transitively closed
// without doing too much work at the leaves of the call tree
public struct Transitively {}
public struct Directly {}

public struct InvalidatedSet<ClosureLevel, Element: Hashable>: Sequence {
  var contents: Set<Element>

  init(_ s: Set<Element> = Set()) {
    self.contents = s
  }
  init<Elements: Sequence>(_ elements: Elements)
  where Elements.Element == Element
  {
    self.init(Set(elements))
  }
  mutating func insert(_ e: Element) {
    contents.insert(e)
  }
  mutating func formUnion<Elements: Sequence>(_ elements: Elements)
  where Elements.Element == Element{
    contents.formUnion(elements)
  }
  public func makeIterator() -> Set<Element>.Iterator {
    contents.makeIterator()
  }
  public func map<R>(_ transform: (Element) -> R) -> InvalidatedArray<ClosureLevel, R> {
    InvalidatedArray(contents.map(transform))
  }
  public func compactMap<R>(_ transform: (Element) -> R? ) -> InvalidatedArray<ClosureLevel, R> {
    InvalidatedArray(contents.compactMap(transform))
  }
}

extension InvalidatedSet where Element: Comparable {
  func sorted() -> InvalidatedArray<ClosureLevel, Element> {
    InvalidatedArray(contents.sorted())
  }
}

public struct InvalidatedArray<ClosureLevel, Element>: Sequence {
  var contents: [Element]

  init(_ s: [Element] = []) {
    self.contents = s
  }
  init<Elements: Sequence>(_ elements: Elements)
  where Elements.Element == Element
  {
    self.init(Array(elements))
  }
  public func makeIterator() -> Array<Element>.Iterator {
    contents.makeIterator()
  }
  public mutating func append(_ e: Element) {
    contents.append(e)
  }
  public func reduce<R: Hashable>(
    into initialResult: InvalidatedSet<ClosureLevel, R>,
    _ updateAccumulatingResult: (inout Set<R>, Element) -> ()
  ) -> InvalidatedSet<ClosureLevel, R> {
    InvalidatedSet(
      contents.reduce(into: initialResult.contents, updateAccumulatingResult))
  }
  public var count: Int { contents.count }
}

public typealias TransitivelyInvalidatedNodeArray = InvalidatedArray<Transitively, ModuleDependencyGraph.Node>
public typealias TransitivelyInvalidatedSourceSet = InvalidatedSet<Transitively, DependencySource>
public typealias TransitivelyInvalidatedInputArray = InvalidatedArray<Transitively, TypedVirtualPath>
public typealias TransitivelyInvalidatedInputSet = InvalidatedSet<Transitively, TypedVirtualPath>
public typealias DirectlyInvalidatedNodeArray = InvalidatedArray<Directly, ModuleDependencyGraph.Node>
public typealias DirectlyInvalidatedNodeSet = InvalidatedSet<Directly, ModuleDependencyGraph.Node>
