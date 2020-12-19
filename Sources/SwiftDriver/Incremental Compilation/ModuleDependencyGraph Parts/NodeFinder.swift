//===-------------------- NodeFinder.swift --------------------------------===//
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

extension ModuleDependencyGraph {

  // Shorthands

  /// The core information for the ModuleDependencyGraph
  /// Isolate in a sub-structure in order to faciliate invariant maintainance
  struct NodeFinder {
    typealias Graph = ModuleDependencyGraph
    
    /// Maps swiftDeps files and DependencyKeys to Nodes
    fileprivate typealias NodeMap = TwoDMap<SwiftDeps?, DependencyKey, Node>
    fileprivate var nodeMap = NodeMap()
    
    /// Since dependency keys use baseNames, they are coarser than individual
    /// decls. So two decls might map to the same key. Given a use, which is
    /// denoted by a node, the code needs to find the files to recompile. So, the
    /// key indexes into the nodeMap, and that yields a submap of nodes keyed by
    /// file. The set of keys in the submap are the files that must be recompiled
    /// for the use.
    /// (In a given file, only one node exists with a given key, but in the future
    /// that would need to change if/when we can recompile a smaller unit than a
    /// source file.)
    
    /// Tracks def-use relationships by DependencyKey.
    private(set)var usesByDef = Multidictionary<DependencyKey, Node>()
  }
}
// MARK: - finding
extension ModuleDependencyGraph.NodeFinder {
  func findFileInterfaceNode(forMock swiftDeps: ModuleDependencyGraph.SwiftDeps
  ) -> Graph.Node?  {
    let fileKey = DependencyKey(fileKeyForMockSwiftDeps: swiftDeps)
    return findNode((swiftDeps, fileKey))
  }
  func findNode(_ mapKey: (Graph.SwiftDeps?, DependencyKey)) -> Graph.Node? {
    nodeMap[mapKey]
  }
  func findCorrespondingImplementation(of n: Graph.Node) -> Graph.Node? {
    n.dependencyKey.correspondingImplementation
      .flatMap {findNode((n.swiftDeps, $0))}
  }
  
  func findNodes(for swiftDeps: Graph.SwiftDeps?) -> [DependencyKey: Graph.Node]? {
    nodeMap[swiftDeps]
  }
  func findNodes(for key: DependencyKey) -> [Graph.SwiftDeps?: Graph.Node]? {
    nodeMap[key]
  }
  
  func forEachUse(of def: Graph.Node, _ fn: (Graph.Node, Graph.SwiftDeps) -> Void) {
    func fnVerifyingSwiftDeps(_ use: Graph.Node) {
      fn(use, useMustHaveSwiftDeps(use))
    }
    usesByDef[def.dependencyKey].map {
      $0.values.forEach(fnVerifyingSwiftDeps)
    }
    // Add in implicit interface->implementation dependency
    findCorrespondingImplementation(of: def)
      .map(fnVerifyingSwiftDeps)
  }

  func forEachUseInOrder(of def: Graph.Node, _ fn: (Graph.Node, Graph.SwiftDeps) -> Void) {
    var uses = [(Graph.Node, Graph.SwiftDeps)]()
    forEachUse(of: def) {
      uses.append(($0, $1))
    }
    uses.sorted {$0.0 < $1.0} .forEach { fn($0.0, $0.1) }
  }

  func mappings(of n: Graph.Node) -> [(Graph.SwiftDeps?, DependencyKey)]
  {
    nodeMap.compactMap {
      k, _ in
      k.0 == n.swiftDeps && k.1 == n.dependencyKey
        ? k
        : nil
    }
  }
  
  func defsUsing(_ n: Graph.Node) -> [DependencyKey] {
    usesByDef.keysContainingValue(n)
  }
}

fileprivate extension ModuleDependencyGraph.Node {
  var mapKey: (Graph.SwiftDeps?, DependencyKey) {
    return (swiftDeps, dependencyKey)
  }
}

// MARK: - inserting

extension ModuleDependencyGraph.NodeFinder {
  
  /// Add `node` to the structure, return the old node if any at those coordinates.
  @discardableResult
  mutating func insert(_ n: Graph.Node) -> Graph.Node? {
    nodeMap.updateValue(n, forKey: n.mapKey)
  }
  
  /// record def-use, return if is new use
  mutating func record(def: DependencyKey, use: Graph.Node) -> Bool {
    verifyUseIsOK(use)
    return usesByDef.addValue(use, forKey: def)
  }
}

// MARK: - removing
extension ModuleDependencyGraph.NodeFinder {
  mutating func remove(_ nodeToErase: Graph.Node) {
    // uses first preserves invariant that every used node is in nodeMap
    removeUsings(of: nodeToErase)
    removeMapping(of: nodeToErase)
  }
  
  private mutating func removeUsings(of nodeToNotUse: Graph.Node) {
    usesByDef.removeValue(nodeToNotUse)
    assert(defsUsing(nodeToNotUse).isEmpty)
  }
  
  private mutating func removeMapping(of nodeToNotMap: Graph.Node) {
    let old = nodeMap.removeValue(forKey: nodeToNotMap.mapKey)
    assert(old == nodeToNotMap, "Should have been there")
    assert(mappings(of: nodeToNotMap).isEmpty)
  }
}

// MARK: - moving
extension ModuleDependencyGraph.NodeFinder {
  /// When integrating a SourceFileDepGraph, there might be a node representing
  /// a Decl that had previously been read as an expat, that is a node
  /// representing a Decl in no known file (to that point). (Recall the the
  /// Frontend processes name lookups as dependencies, but does not record in
  /// which file the name was found.) In such a case, it is necessary to move
  /// the node to the proper collection.
  ///
  /// Now that nodes are immutable, this function needs to replace the node
  mutating func replace(_ original: Graph.Node,
                        newSwiftDeps: Graph.SwiftDeps,
                        newFingerprint: String?
  ) -> Graph.Node {
    let replacement = Graph.Node(key: original.dependencyKey,
                                 fingerprint: newFingerprint,
                                 swiftDeps: newSwiftDeps)
    usesByDef.replace(original, with: replacement, forKey: original.dependencyKey)
    nodeMap.removeValue(forKey: original.mapKey)
    nodeMap.updateValue(replacement, forKey: replacement.mapKey)
    return replacement
  }
}

// MARK: - asserting & verifying
extension ModuleDependencyGraph.NodeFinder {
  func verify() -> Bool {
    verifyNodeMap()
    verifyUsesByDef()
    return true
  }
  
  private func verifyNodeMap() {
    var nodes = [Set<Graph.Node>(), Set<Graph.Node>()]
    nodeMap.verify {
      _, v, submapIndex in
      if let prev = nodes[submapIndex].update(with: v) {
        fatalError("\(v) is also in nodeMap at \(prev), submap: \(submapIndex)")
      }
      v.verify()
    }
  }
  
  private func verifyUsesByDef() {
    usesByDef.forEach {
      def, use in
      // def may have disappeared from graph, nothing to do
      verifyUseIsOK(use)
    }
  }
  
  private func useMustHaveSwiftDeps(_ n: Graph.Node) -> Graph.SwiftDeps {
    assert(verifyUseIsOK(n))
    return n.swiftDeps!
  }
  
  @discardableResult
  private func verifyUseIsOK(_ n: Graph.Node) -> Bool {
    verifyUsedIsNotExpat(n)
    verifyNodeIsMapped(n)
    return true
  }
  
  private func verifyNodeIsMapped(_ n: Graph.Node) {
    if findNode(n.mapKey) == nil {
      fatalError("\(n) should be mapped")
    }
  }
  
  @discardableResult
  private func verifyUsedIsNotExpat(_ use: Graph.Node) -> Bool {
    guard use.isExpat else { return true }
    fatalError("An expat is not defined anywhere and thus cannot be used")
  }
}
// MARK: - key helpers

fileprivate extension DependencyKey {
  init(fileKeyForMockSwiftDeps swiftDeps: ModuleDependencyGraph.SwiftDeps) {
    self.init(aspect: .interface,
              designator:
                .sourceFileProvide(name: swiftDeps.sourceFileProvidesNameForMocking)
    )
  }
}
fileprivate extension ModuleDependencyGraph.SwiftDeps {
  var sourceFileProvidesNameForMocking: String {
    // Only when mocking are these two guaranteed to be the same
    file.name
  }
}
