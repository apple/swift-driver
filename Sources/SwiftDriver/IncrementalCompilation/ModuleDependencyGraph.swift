//===------- ModuleDependencyGraph.swift ----------------------------------===//
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
import Foundation
import TSCBasic
import TSCUtility
import SwiftOptions


// MARK: - ModuleDependencyGraph

/*@_spi(Testing)*/ public final class ModuleDependencyGraph {

  var nodeFinder = NodeFinder()
  
  /// When integrating a change, want to find untraced nodes so we can kick off jobs that have not been
  /// kicked off yet
  private var tracedNodes = Set<Node>()

  /// Maps input files (e.g. .swift) to and from the DependencySource object
  private(set) var inputDependencySourceMap = BidirectionalMap<TypedVirtualPath, DependencySource>()

  // The set of paths to external dependencies known to be in the graph
  public internal(set) var fingerprintedExternalDependencies = Set<FingerprintedExternalDependency>()

  let options: IncrementalCompilationState.Options
  let reporter: IncrementalCompilationState.Reporter?
  let fileSystem: FileSystem
  
  private let diagnosticEngine: DiagnosticsEngine
  
  public init(
    diagnosticEngine: DiagnosticsEngine,
    reporter: IncrementalCompilationState.Reporter?,
    fileSystem: FileSystem,
    options: IncrementalCompilationState.Options
  ) {
    self.reporter = reporter
    self.diagnosticEngine = diagnosticEngine
    self.options = options
    self.fileSystem = fileSystem
  }

  var isCrossModuleIncrementalBuildEnabled: Bool {
    self.options.contains(.enableCrossModuleIncrementalBuild)
  }
}

// MARK: - initial build only
extension ModuleDependencyGraph {
  /// Builds an empty `ModuleDependencyGraph` for a compilation with the
  /// given input files.
  static func buildEmptyGraph<Inputs: Sequence>(
    for inputFiles: Inputs,
    diagnosticEngine: DiagnosticsEngine,
    outputFileMap: OutputFileMap,
    options: IncrementalCompilationState.Options,
    reporter: IncrementalCompilationState.Reporter?,
    filesystem: FileSystem
  ) -> ModuleDependencyGraph
    where Inputs.Element == TypedVirtualPath
  {
    let emptyGraph = ModuleDependencyGraph(diagnosticEngine: diagnosticEngine,
                                           reporter: reporter,
                                           fileSystem: filesystem,
                                           options: options)

    for input in inputFiles {
      guard let swiftDepsFile = outputFileMap.existingOutput(inputFile: input.file,
                                                             outputType: .swiftDeps) else {
        continue
      }

      assert(swiftDepsFile.extension == FileType.swiftDeps.rawValue)
      let typedSwiftDepsFile = TypedVirtualPath(file: swiftDepsFile, type: .swiftDeps)
      let dependencySource = DependencySource(typedSwiftDepsFile)
      emptyGraph.inputDependencySourceMap[input] = dependencySource
    }
    return emptyGraph
  }

  /// Builds a graph
  /// Returns nil if some input (i.e. .swift file) has no corresponding swiftdeps file.
  /// Returns a list of inputs whose swiftdeps files could not be read
  static func buildInitialGraph<Inputs: Sequence>(
    diagnosticEngine: DiagnosticsEngine,
    inputs: Inputs,
    previousInputs: Set<VirtualPath>,
    outputFileMap: OutputFileMap,
    options: IncrementalCompilationState.Options,
    remarkDisabled: (String) -> Diagnostic.Message,
    reporter: IncrementalCompilationState.Reporter?,
    fileSystem: FileSystem
  ) -> (
    ModuleDependencyGraph,
    inputsAndMalformedSwiftDeps: [(TypedVirtualPath, VirtualPath)]
  )?
    where Inputs.Element == TypedVirtualPath
  {
    let graph = Self(
      diagnosticEngine: diagnosticEngine,
      reporter: reporter,
	  fileSystem: fileSystem,
      options: options)

    let inputsAndSwiftdeps = inputs.map { input in
      (input, outputFileMap.existingOutput(inputFile: input.file,
                                           outputType: .swiftDeps))
    }
    for isd in inputsAndSwiftdeps where isd.1 == nil {
      // The legacy driver fails silently here.
      diagnosticEngine.emit(
        remarkDisabled("\(isd.0.file.basename) has no swiftDeps file")
      )
      return nil
    }
    let inputsAndMalformedSwiftDeps = inputsAndSwiftdeps.compactMap {
      input, swiftDepsFile -> (TypedVirtualPath, VirtualPath)? in
      guard let swiftDepsFile = swiftDepsFile
      else {
        return nil
      }
      assert(swiftDepsFile.extension == FileType.swiftDeps.rawValue)
      let typedSwiftDepsFile = TypedVirtualPath(file: swiftDepsFile, type: .swiftDeps)
      let dependencySource = DependencySource(typedSwiftDepsFile)
      graph.inputDependencySourceMap[input] = dependencySource
      guard previousInputs.contains(input.file)
      else {
        // do not try to read swiftdeps of a new input
        return nil
      }
      guard let _ = graph.integrate(swiftDeps: typedSwiftDepsFile)
      else {
        return (input, swiftDepsFile) // remember the errorred files
      }
      return nil
    }
    return (graph, inputsAndMalformedSwiftDeps: inputsAndMalformedSwiftDeps)
  }
}

// MARK: - Integrating
extension ModuleDependencyGraph {
  /// Integrate one swiftDeps, corresponding to an input, and return the changed nodes
  /// Return nil for errror
  public func integrate(swiftDeps: TypedVirtualPath) -> Set<Node>? {
    precondition(swiftDeps.type == .swiftDeps)
    let dependencySource = DependencySource(swiftDeps)
    return integrate(from: dependencySource)
  }

  public func integrate(from dependencySource: DependencySource) -> Set<Node>?  {
    precondition(dependencySource.typedFile.type == .swiftDeps)
    guard let sourceGraph = dependencySource.read(
            in: fileSystem,
            reporter: reporter)
    else {
      return nil
    }
    return integrate(sourceGraph: sourceGraph)
  }

  public func integrate(sourceGraph: SourceFileDependencyGraph) -> Set<Node>? {
    let results = Integrator.integrateAndCollectExternalDepNodes(from: sourceGraph,
                                                                 into: self)
    guard let externallyCausedChanges =
            integrate(discoveredExternalDependencies: results.discoveredExternalDependencies)
    else {
      return nil
    }
    return results.allInvalidatedNodes.union(externallyCausedChanges)
  }

  /// Returns changed nodes
  private func integrate(
    discoveredExternalDependencies: Set<FingerprintedExternalDependency>
  ) -> Set<Node>?
  {
    var workList = discoveredExternalDependencies
    var changedNodes = Set<Node>()
    while let edp = workList.first {
      guard fingerprintedExternalDependencies.insert(edp).inserted else {
        continue
      }
      let resultIfOK = integrate(
        externalDependency: edp,
        fileSystem: fileSystem)
      if let result = resultIfOK {
        changedNodes.formUnion(result.allInvalidatedNodes)
        workList.formUnion(result.discoveredExternalDependencies)
      }
      else {
        return nil // give up
      }
      workList.remove(edp)
    }
    return changedNodes
  }

  private func integrate(
    externalDependency: FingerprintedExternalDependency,
    fileSystem: FileSystem
  ) -> Integrator.Results? {
    guard let dependencySource = externalDependency.incrementalDependencySource else {
      return Integrator.Results()
    }
    reporter?.report("integrating incremental external dependency",
                     dependencySource.typedFile)
    guard let sourceGraph = dependencySource.read(
            in: fileSystem,
            reporter: reporter)
    else {
      return nil
    }
    let results = Integrator.integrateAndCollectExternalDepNodes(
      from: sourceGraph,
      into: self
    )
    return results
  }

}
// MARK: - Scheduling the first wave
extension ModuleDependencyGraph {
  /// Find all the sources that depend on `sourceFile`. For some source files, these will be
  /// speculatively scheduled in the first wave.
  func collectInputsTransitivelyInvalidatedBy(
    input sourceFile: TypedVirtualPath
  ) -> [TypedVirtualPath] {
    var allDependencySourcesToRecompile = Set<DependencySource>()

    let dependencySource = inputDependencySourceMap[sourceFile]

    for dependencySourceToRecompile in
      collectSwiftDepsTransitivelyUsing( dependencySource ) {
      if dependencySourceToRecompile != dependencySource {
        allDependencySourcesToRecompile.insert(dependencySourceToRecompile)
      }
    }
    return allDependencySourcesToRecompile.map {
      let dependentSource = inputDependencySourceMap[$0]
      self.reporter?.report(
        "Found dependent of \(sourceFile.file.basename):", dependentSource)
      return dependentSource
    }
  }

  /// Find all the swiftDeps files that depend on `dependencySource`.
  /// Really private, except for testing.
  /*@_spi(Testing)*/ public func collectSwiftDepsTransitivelyUsing(
    _ dependencySource: DependencySource  ) -> Set<DependencySource> {
    let nodes = nodeFinder.findNodes(for: dependencySource) ?? [:]
    /// Tests expect this to be reflexive
    return collectSwiftDepsUsingTransitivelyInvalidated(nodes: nodes.values)
  }
}
// MARK: - Scheduling the 2nd wave
extension ModuleDependencyGraph {
  /// After `source` has been compiled, figure out what other source files need compiling.
  /// Used to schedule the 2nd wave.
  /// Return nil in case of an error.
  func collectInputsInvalidated(
    byCompiling input: TypedVirtualPath,
    on fileSystem: FileSystem
  ) -> [TypedVirtualPath]? {
    collectInputsRequiringCompilation(
      byCompiling: input,
      dependencySource: inputDependencySourceMap[input],
      on: fileSystem)
  }

  /// After a compile job has finished, read its swiftDeps file and return the source files needing
  /// recompilation.
  /// Return nil in case of an error.
  /// May return a source that has already been compiled.
  private func     collectInputsRequiringCompilation(
    byCompiling: TypedVirtualPath,
    dependencySource: DependencySource,
    on fileSystem: FileSystem
  ) -> [TypedVirtualPath]? {
    let swiftDeps = inputDependencySourceMap[byCompiling].typedFile
    let changedNodesIfOK = integrate(swiftDeps: swiftDeps)
    guard let changedNodes = changedNodesIfOK else {
      return nil
    }
    return collectSwiftDepsUsingTransitivelyInvalidated(nodes: changedNodes)
      .map { inputDependencySourceMap[$0] }
  }
}

// MARK: - Scheduling either wave
extension ModuleDependencyGraph {
  /// Find all the swiftDeps affected when the nodes change.
  /*@_spi(Testing)*/ public func collectSwiftDepsUsingTransitivelyInvalidated<Nodes: Sequence>(
    nodes: Nodes
  ) -> Set<DependencySource>
    where Nodes.Element == Node
  {
    let affectedNodes = Tracer.collectPreviouslyUntracedNodesUsing(
      defNodes: nodes,
      in: self,
      diagnosticEngine: diagnosticEngine)
      .tracedUses
    return Set(affectedNodes.compactMap {$0.dependencySource})
  }

  /*@_spi(Testing)*/ public func collectUntracedNodesDirectlyUsing(
    _ fingerprintedExternalDependency: FingerprintedExternalDependency
  ) -> [ModuleDependencyGraph.Node] {
    // These nodes will depend on the *interface* of the external Decl.
    let key = DependencyKey(interfaceFor: fingerprintedExternalDependency.externalDependency)
    // DependencySource is OK as a nil placeholder because it's only used to find
    // the corresponding implementation node and there won't be any for an
    // external dependency node.
    let node = Node(key: key,
                    fingerprint: fingerprintedExternalDependency.fingerprint,
                    dependencySource: nil)
    return nodeFinder
      .orderedUses(of: node)
      .filter({ use in isUntraced(use) })
  }
}
fileprivate extension DependencyKey {
  init(interfaceFor dep: ExternalDependency) {
    self.init(aspect: .interface,
              designator: .externalDepend(dep))
  }
}
// MARK: - tracking traced nodes
extension ModuleDependencyGraph {

  func isUntraced(_ n: Node) -> Bool {
    !isTraced(n)
  }
  func isTraced(_ n: Node) -> Bool {
    tracedNodes.contains(n)
  }
  func amTracing(_ n: Node) {
    tracedNodes.insert(n)
  }
  func ensureGraphWillRetraceDependents<Nodes: Sequence>(of nodes: Nodes)
    where Nodes.Element == Node
  {
    nodes.forEach { tracedNodes.remove($0) }
  }
}

// MARK: - verification
extension ModuleDependencyGraph {
  @discardableResult
  func verifyGraph() -> Bool {
    nodeFinder.verify()
  }
}
// MARK: - debugging
extension ModuleDependencyGraph {
  func emitDotFile(_ g: SourceFileDependencyGraph) {
    // TODO: Incremental emitDotFIle
    fatalError("unimplmemented, writing dot file of dependency graph")
  }
}

// MARK: - Serialization

extension ModuleDependencyGraph {
  /// The leading signature of this file format.
  fileprivate static let signature = "DDEP"
  /// The expected version number of the serialized dependency graph.
  ///
  /// - WARNING: You *must* increment the minor version number when making any
  ///            changes to the underlying serialization format.
  fileprivate static let version = Version(1, 0, 0)

  /// The IDs of the records used by the module dependency graph.
  fileprivate enum RecordID: UInt64 {
    case metadata           = 1
    case moduleDepGraphNode = 2
    case dependsOnNode      = 3
    case useIDNode          = 4
    case externalDepNode    = 5
    case identifierNode     = 6

    /// The human-readable name of this record.
    ///
    /// This data is emitted into the block info field for each record so tools
    /// like llvm-bcanalyzer can be used to more effectively debug serialized
    /// dependency graphs.
    var humanReadableName: String {
      switch self {
      case .metadata:
        return "METADATA"
      case .moduleDepGraphNode:
        return "MODULE_DEP_GRAPH_NODE"
      case .dependsOnNode:
        return "DEPENDS_ON_NODE"
      case .useIDNode:
        return "USE_ID_NODE"
      case .externalDepNode:
        return "EXTERNAL_DEP_NODE"
      case .identifierNode:
        return "IDENTIFIER_NODE"
      }
    }
  }

  fileprivate enum ReadError: Error {
    case badMagic
    case noRecordBlock
    case malformedMetadataRecord
    case unexpectedMetadataRecord
    case malformedFingerprintRecord
    case malformedIdentifierRecord
    case malformedModuleDepGraphNodeRecord
    case malformedDependsOnRecord
    case malformedExternalDepNodeRecord
    case unknownRecord
    case unexpectedSubblock
    case bogusNameOrContext
    case unknownKind
    case unknownDependencySourceExtension
  }

  /// Attempts to read a serialized dependency graph from the given path.
  ///
  /// - Parameters:
  ///   - path: The absolute path to the file to be read.
  ///   - fileSystem: The file system on which to search.
  ///   - diagnosticEngine: The diagnostics engine.
  ///   - reporter: An optional reporter used to log information about
  /// - Throws: An error describing any failures to read the graph from the given file.
  /// - Returns: A fully deserialized ModuleDependencyGraph.
  static func read(
    from path: VirtualPath,
    on fileSystem: FileSystem,
    diagnosticEngine: DiagnosticsEngine,
    reporter: IncrementalCompilationState.Reporter?,
    options: IncrementalCompilationState.Options
  ) throws -> ModuleDependencyGraph {
    let data = try fileSystem.readFileContents(path)

    struct Visitor: BitstreamVisitor {
      private let graph: ModuleDependencyGraph
      var majorVersion: UInt64?
      var minorVersion: UInt64?
      var compilerVersionString: String?

      // The empty string is hardcoded as identifiers[0]
      private var identifiers: [String] = [""]
      private var currentDefKey: DependencyKey? = nil
      private var nodeUses: [DependencyKey: [Int]] = [:]
      private var allNodes: [Node] = []

      init(
        diagnosticEngine: DiagnosticsEngine,
        reporter: IncrementalCompilationState.Reporter?,
        fileSystem: FileSystem,
        options: IncrementalCompilationState.Options
      ) {
        self.graph = ModuleDependencyGraph(
          diagnosticEngine: diagnosticEngine,
          reporter: reporter,
		  fileSystem: fileSystem,
          options: options)
      }

      func finalizeGraph() -> ModuleDependencyGraph {
        for (dependencyKey, useIDs) in self.nodeUses {
          for useID in useIDs {
            let isNewUse = self.graph.nodeFinder
              .record(def: dependencyKey, use: self.allNodes[useID])
            assert(isNewUse, "Duplicate use def-use arc in graph?")
          }
        }
        return self.graph
      }

      func validate(signature: Bitcode.Signature) throws {
        guard signature == .init(string: ModuleDependencyGraph.signature) else {
          throw ReadError.badMagic
        }
      }

      mutating func shouldEnterBlock(id: UInt64) throws -> Bool {
        return true
      }

      mutating func didExitBlock() throws {}

      private mutating func finalize(node newNode: Node) {
        self.allNodes.append(newNode)
        let oldNode = self.graph.nodeFinder.insert(newNode)
        assert(oldNode == nil,
               "Integrated the same node twice: \(oldNode!), \(newNode)")
      }

      mutating func visit(record: BitcodeElement.Record) throws {
        guard let kind = RecordID(rawValue: record.id) else {
          throw ReadError.unknownRecord
        }

        switch kind {
        case .metadata:
          // If we've already read metadata, this is an unexpected duplicate.
          guard self.majorVersion == nil, self.minorVersion == nil, self.compilerVersionString == nil else {
            throw ReadError.unexpectedMetadataRecord
          }
          guard record.fields.count == 2,
                case .blob(let compilerVersionBlob) = record.payload,
                let compilerVersionString = String(data: compilerVersionBlob, encoding: .utf8)
          else { throw ReadError.malformedMetadataRecord }

          self.majorVersion = record.fields[0]
          self.minorVersion = record.fields[1]
          self.compilerVersionString = compilerVersionString
        case .moduleDepGraphNode:
          let kindCode = record.fields[0]
          guard record.fields.count == 7,
                let declAspect = DependencyKey.DeclAspect(record.fields[1]),
                record.fields[2] < identifiers.count,
                record.fields[3] < identifiers.count,
                case .blob(let fingerprintBlob) = record.payload,
                let fingerprintStr = String(data: fingerprintBlob, encoding: .utf8)
          else {
            throw ReadError.malformedModuleDepGraphNodeRecord
          }
          let context = identifiers[Int(record.fields[2])]
          let identifier = identifiers[Int(record.fields[3])]
          let designator = try DependencyKey.Designator(
            kindCode: kindCode, context: context, name: identifier)
          let key = DependencyKey(aspect: declAspect, designator: designator)
          let hasSwiftDeps = Int(record.fields[4]) != 0
          let swiftDepsStr = hasSwiftDeps ? identifiers[Int(record.fields[5])] : nil
          let hasFingerprint = Int(record.fields[6]) != 0
          let fingerprint = hasFingerprint ? fingerprintStr : nil
          guard let dependencySource = try swiftDepsStr
                  .map({ try VirtualPath(path: $0) })
                  .map(DependencySource.init)
          else {
            throw ReadError.unknownDependencySourceExtension
          }
          self.finalize(node: Node(key: key,
                                   fingerprint: fingerprint,
                                   dependencySource: dependencySource))
        case .dependsOnNode:
          let kindCode = record.fields[0]
          guard record.fields.count == 4,
                let declAspect = DependencyKey.DeclAspect(record.fields[1]),
                record.fields[2] < identifiers.count,
                record.fields[3] < identifiers.count
          else {
            throw ReadError.malformedDependsOnRecord
          }
          let context = identifiers[Int(record.fields[2])]
          let identifier = identifiers[Int(record.fields[3])]
          let designator = try DependencyKey.Designator(
            kindCode: kindCode, context: context, name: identifier)
          self.currentDefKey = DependencyKey(aspect: declAspect, designator: designator)
        case .useIDNode:
          guard let key = self.currentDefKey, record.fields.count == 1 else {
            throw ReadError.malformedDependsOnRecord
          }
          self.nodeUses[key, default: []].append(Int(record.fields[0]))
        case .externalDepNode:
          guard record.fields.count == 2,
                record.fields[0] < identifiers.count,
                case .blob(let fingerprintBlob) = record.payload,
                let fingerprintStr = String(data: fingerprintBlob, encoding: .utf8)
          else {
            throw ReadError.malformedExternalDepNodeRecord
          }
          let path = identifiers[Int(record.fields[0])]
          let hasFingerprint = Int(record.fields[1]) != 0
          let fingerprint = hasFingerprint ? fingerprintStr : nil
          self.graph.fingerprintedExternalDependencies.insert(
            FingerprintedExternalDependency(try ExternalDependency(path), fingerprint))
        case .identifierNode:
          guard record.fields.count == 0,
                case .blob(let identifierBlob) = record.payload,
                let identifier = String(data: identifierBlob, encoding: .utf8)
          else {
            throw ReadError.malformedIdentifierRecord
          }
          identifiers.append(identifier)
        }
      }
    }

    var visitor = Visitor(diagnosticEngine: diagnosticEngine,
                          reporter: reporter,
                          fileSystem: fileSystem,
                          options: options)
    try Bitcode.read(bytes: data, using: &visitor)
    guard let major = visitor.majorVersion,
          let minor = visitor.minorVersion,
          visitor.compilerVersionString != nil,
          Version(Int(major), Int(minor), 0) == Self.version
    else {
      throw ReadError.malformedMetadataRecord
    }
    return visitor.finalizeGraph()
  }
}

extension ModuleDependencyGraph {
  /// Attempts to serialize this dependency graph and write its contents
  /// to the given file path.
  ///
  /// Should serialization fail, the driver must emit an error *and* moreover
  /// the build record should reflect that the incremental build failed. This
  /// prevents bogus priors from being picked up the next time the build is run.
  /// It's better for us to just redo the incremental build than wind up with
  /// corrupted dependency state.
  ///
  /// - Parameters:
  ///   - path: The location to write the data for this file.
  ///   - fileSystem: The file system for this location.
  ///   - compilerVersion: A string containing version information for the
  ///                      driver used to create this file.
  func write(
    to path: VirtualPath,
    on fileSystem: FileSystem,
    compilerVersion: String
  ) {
    let data = ModuleDependencyGraph.Serializer.serialize(self, compilerVersion)

    do {
      try fileSystem.writeFileContents(path,
                                       bytes: data,
                                       atomically: true)
    } catch {
      diagnosticEngine.emit(.error_could_not_write_dep_graph(to: path))
    }
  }

  fileprivate final class Serializer {
    let compilerVersion: String
    let stream = BitstreamWriter()
    private var abbreviations = [RecordID: Bitstream.AbbreviationID]()
    private var identifiersToWrite = [String]()
    private var identifierIDs = [String: Int]()
    private var lastIdentifierID: Int = 1
    fileprivate private(set) var nodeIDs = [Node: Int]()
    private var lastNodeID: Int = 0

    private init(compilerVersion: String) {
      self.compilerVersion = compilerVersion
    }

    private func emitSignature() {
      for c in ModuleDependencyGraph.signature {
        self.stream.writeASCII(c)
      }
    }

    private func emitBlockID(_ ID: Bitstream.BlockID, _ name: String) {
      self.stream.writeRecord(Bitstream.BlockInfoCode.setBID) {
        $0.append(ID)
      }

      // Emit the block name if present.
      guard !name.isEmpty else {
        return
      }

      self.stream.writeRecord(Bitstream.BlockInfoCode.blockName) { buffer in
        buffer.append(name)
      }
    }

    private func emitRecordID(_ id: RecordID) {
      self.stream.writeRecord(Bitstream.BlockInfoCode.setRecordName) {
        $0.append(id)
        $0.append(id.humanReadableName)
      }
    }

    private func writeBlockInfoBlock() {
      self.stream.writeBlockInfoBlock {
        self.emitBlockID(.firstApplicationID, "RECORD_BLOCK")
        self.emitRecordID(.metadata)
        self.emitRecordID(.moduleDepGraphNode)
        self.emitRecordID(.useIDNode)
        self.emitRecordID(.externalDepNode)
        self.emitRecordID(.identifierNode)
      }
    }

    private func writeMetadata() {
      self.stream.writeRecord(self.abbreviations[.metadata]!, {
        $0.append(RecordID.metadata)
        // Major version
        $0.append(1 as UInt32)
        // Minor version
        $0.append(0 as UInt32)
      },
      blob: self.compilerVersion)
    }

    private func addIdentifier(_ str: String) {
      guard !str.isEmpty && self.identifierIDs[str] == nil else {
        return
      }

      defer { self.lastIdentifierID += 1 }
      self.identifierIDs[str] = self.lastIdentifierID
      self.identifiersToWrite.append(str)
    }

    private func lookupIdentifierCode(for string: String) -> UInt32 {
      guard !string.isEmpty else {
        return 0
      }

      return UInt32(self.identifierIDs[string]!)
    }

    private func cacheNodeID(for node: Node) {
      defer { self.lastNodeID += 1 }
      nodeIDs[node] = self.lastNodeID
    }

    private func populateCaches(from graph: ModuleDependencyGraph) {
      graph.nodeFinder.forEachNode { node in
        self.cacheNodeID(for: node)

        if let dependencySourceFileName = node.dependencySource?.file.name {
          self.addIdentifier(dependencySourceFileName)
        }
        if let context = node.key.designator.context {
          self.addIdentifier(context)
        }
        if let name = node.key.designator.name {
          self.addIdentifier(name)
        }
      }

      for key in graph.nodeFinder.usesByDef.keys {
        if let context = key.designator.context {
          self.addIdentifier(context)
        }
        if let name = key.designator.name {
          self.addIdentifier(name)
        }
      }

      for edF in graph.fingerprintedExternalDependencies {
        self.addIdentifier(edF.externalDependency.file.name)
      }

      for str in self.identifiersToWrite {
        self.stream.writeRecord(self.abbreviations[.identifierNode]!, {
          $0.append(RecordID.identifierNode)
        }, blob: str)
      }
    }

    private func registerAbbreviations() {
      self.abbreviate(.metadata, [
        .literal(RecordID.metadata.rawValue),
        // Major version
        .fixed(bitWidth: 16),
        // Minor version
        .fixed(bitWidth: 16),
        // Frontend version
        .blob,
      ])
      self.abbreviate(.moduleDepGraphNode, [
        .literal(RecordID.moduleDepGraphNode.rawValue),
        // dependency kind discriminator
        .fixed(bitWidth: 3),
        // dependency decl aspect discriminator
        .fixed(bitWidth: 1),
        // dependency context
        .vbr(chunkBitWidth: 13),
        // dependency name
        .vbr(chunkBitWidth: 13),
        // swiftdeps?
        .fixed(bitWidth: 1),
        // swiftdeps path
        .vbr(chunkBitWidth: 13),
        // fingerprint?
        .fixed(bitWidth: 1),
        // fingerprint bytes
        .blob,
      ])
      self.abbreviate(.dependsOnNode, [
        .literal(RecordID.dependsOnNode.rawValue),
        // dependency kind discriminator
        .fixed(bitWidth: 3),
        // dependency decl aspect discriminator
        .fixed(bitWidth: 1),
        // dependency context
        .vbr(chunkBitWidth: 13),
        // dependency name
        .vbr(chunkBitWidth: 13),
      ])

      self.abbreviate(.useIDNode, [
        .literal(RecordID.useIDNode.rawValue),
        // node ID
        .vbr(chunkBitWidth: 13),
      ])
      self.abbreviate(.externalDepNode, [
        .literal(RecordID.externalDepNode.rawValue),
        // path ID
        .vbr(chunkBitWidth: 13),
        // fingerprint?
        .fixed(bitWidth: 1),
        // fingerprint bytes
        .blob
      ])
      self.abbreviate(.identifierNode, [
        .literal(RecordID.identifierNode.rawValue),
        // identifier data
        .blob
      ])
    }

    private func abbreviate(
      _ record: RecordID,
      _ operands: [Bitstream.Abbreviation.Operand]
    ) {
      self.abbreviations[record]
        = self.stream.defineAbbreviation(Bitstream.Abbreviation(operands))
    }

    public static func serialize(
      _ graph: ModuleDependencyGraph,
      _ compilerVersion: String
    ) -> ByteString {
      let serializer = Serializer(compilerVersion: compilerVersion)
      serializer.emitSignature()
      serializer.writeBlockInfoBlock()

      serializer.stream.withSubBlock(.firstApplicationID, abbreviationBitWidth: 8) {
        serializer.registerAbbreviations()

        serializer.writeMetadata()

        serializer.populateCaches(from: graph)

        graph.nodeFinder.forEachNode { node in
          serializer.stream.writeRecord(serializer.abbreviations[.moduleDepGraphNode]!, {
            $0.append(RecordID.moduleDepGraphNode)
            $0.append(node.key.designator.code)
            $0.append(node.key.aspect.code)
            $0.append(serializer.lookupIdentifierCode(
                        for: node.key.designator.context ?? ""))
            $0.append(serializer.lookupIdentifierCode(
                        for: node.key.designator.name ?? ""))
            $0.append((node.dependencySource != nil) ? UInt32(1) : UInt32(0))
            $0.append(serializer.lookupIdentifierCode(
                        for: node.dependencySource?.file.name ?? ""))
            $0.append((node.fingerprint != nil) ? UInt32(1) : UInt32(0))
          }, blob: node.fingerprint ?? "")
        }

        for key in graph.nodeFinder.usesByDef.keys {
          serializer.stream.writeRecord(serializer.abbreviations[.dependsOnNode]!) {
            $0.append(RecordID.dependsOnNode)
            $0.append(key.designator.code)
            $0.append(key.aspect.code)
            $0.append(serializer.lookupIdentifierCode(
                        for: key.designator.context ?? ""))
            $0.append(serializer.lookupIdentifierCode(
                        for: key.designator.name ?? ""))
          }
          for use in graph.nodeFinder.usesByDef[key, default: []] {
            guard let useID = serializer.nodeIDs[use] else {
              fatalError("Node ID was not registered! \(use)")
            }

            serializer.stream.writeRecord(serializer.abbreviations[.useIDNode]!) {
              $0.append(RecordID.useIDNode)
              $0.append(UInt32(useID))
            }
          }
        }

        for fingerprintedExternalDependency in graph.fingerprintedExternalDependencies {
          serializer.stream.writeRecord(serializer.abbreviations[.externalDepNode]!, {
            $0.append(RecordID.externalDepNode)
            $0.append(serializer.lookupIdentifierCode(
                        for: fingerprintedExternalDependency.externalDependency.file.name))
            $0.append((fingerprintedExternalDependency.fingerprint != nil) ? UInt32(1) : UInt32(0))
          }, 
          blob: (fingerprintedExternalDependency.fingerprint ?? ""))
        }
      }
      return ByteString(serializer.stream.data)
    }
  }
}

fileprivate extension DependencyKey.DeclAspect {
  init?(_ c: UInt64) {
    switch c {
    case 0:
      self = .interface
    case 1:
      self = .implementation
    default:
      return nil
    }
  }

  var code: UInt32 {
    switch self {
    case .interface:
      return 0
    case .implementation:
      return 1
    }
  }
}

fileprivate extension DependencyKey.Designator {
  init(kindCode: UInt64, context: String, name: String) throws {
    func mustBeEmpty(_ s: String) throws {
      guard s.isEmpty else {
        throw ModuleDependencyGraph.ReadError.bogusNameOrContext
      }
    }

    switch kindCode {
    case 0:
      try mustBeEmpty(context)
      self = .topLevel(name: name)
    case 1:
      try mustBeEmpty(name)
      self = .nominal(context: context)
    case 2:
      try mustBeEmpty(name)
      self = .potentialMember(context: context)
    case 3:
      self = .member(context: context, name: name)
    case 4:
      try mustBeEmpty(context)
      self = .dynamicLookup(name: name)
    case 5:
      try mustBeEmpty(context)
      self = .externalDepend(try ExternalDependency(name))
    case 6:
      try mustBeEmpty(context)
      self = .sourceFileProvide(name: name)
    default: throw ModuleDependencyGraph.ReadError.unknownKind
    }
  }

  var code: UInt32 {
    switch self {
    case .topLevel(name: _):
      return 0
    case .nominal(context: _):
      return 1
    case .potentialMember(context: _):
      return 2
    case .member(context: _, name: _):
      return 3
    case .dynamicLookup(name: _):
      return 4
    case .externalDepend(_):
      return 5
    case .sourceFileProvide(name: _):
      return 6
    }
  }

  var context: String? {
    switch self {
    case .topLevel(name: _):
      return nil
    case .dynamicLookup(name: _):
      return nil
    case .externalDepend(_):
      return nil
    case .sourceFileProvide(name: _):
      return nil
    case .nominal(context: let context):
      return context
    case .potentialMember(context: let context):
      return context
    case .member(context: let context, name: _):
      return context
    }
  }

  var name: String? {
    switch self {
    case .topLevel(name: let name):
      return name
    case .dynamicLookup(name: let name):
      return name
    case .externalDepend(let path):
      return path.file.name
    case .sourceFileProvide(name: let name):
      return name
    case .member(context: _, name: let name):
      return name
    case .nominal(context: _):
      return nil
    case .potentialMember(context: _):
      return nil
    }
  }
}

extension Diagnostic.Message {
  fileprivate static func error_could_not_write_dep_graph(
    to path: VirtualPath
  ) -> Diagnostic.Message {
    .error("could not write driver dependency graph to \(path)")
  }
}

// MARK: - Checking Serialization

extension ModuleDependencyGraph {
  func matches(_ other: ModuleDependencyGraph) -> Bool {
    guard nodeFinder.matches(other.nodeFinder),
      tracedNodes.matches(other.tracedNodes),
      inputDependencySourceMap.matches(other.inputDependencySourceMap),
      fingerprintedExternalDependencies.matches(other.fingerprintedExternalDependencies)
    else {
      return false
    }
    return true
  }
}

extension Set where Element == ModuleDependencyGraph.Node {
  fileprivate func matches(_ other: Self) -> Bool {
    self == other
  }
}

extension BidirectionalMap where T1 == TypedVirtualPath, T2 == DependencySource {
  fileprivate func matches(_ other: Self) -> Bool {
    self == other
  }
}

extension Set where Element == FingerprintedExternalDependency {
  fileprivate func matches(_ other: Self) -> Bool {
    self == other
  }
}
