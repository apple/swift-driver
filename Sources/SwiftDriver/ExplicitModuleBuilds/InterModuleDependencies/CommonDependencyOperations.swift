//===----------------- CommonDependencyOperations.swift -------------------===//
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

import func TSCBasic.topologicalSort

@_spi(Testing) public extension InterModuleDependencyGraph {
  /// For targets that are built alongside the driver's current module, the scanning action will report them as
  /// textual targets to be built from source. Because we can rely on these targets to have been built prior
  /// to the driver's current target, we resolve such external targets as prebuilt binary modules, in the graph.
  mutating func resolveExternalDependencies(for externalTargetModuleDetailsMap: ExternalTargetModuleDetailsMap)
  throws {
    for (externalModuleId, externalModuleDetails) in externalTargetModuleDetailsMap {
      let externalModulePath = externalModuleDetails.path
      // Replace the occurrence of a Swift module to-be-built from source-file
      // to an info that describes a pre-built binary module.
      let swiftModuleId: ModuleDependencyId = .swift(externalModuleId.moduleName)
      let prebuiltModuleId: ModuleDependencyId = .swiftPrebuiltExternal(externalModuleId.moduleName)
      if let currentInfo = modules[swiftModuleId],
         externalModuleId.moduleName != mainModuleName {
        let newExternalModuleDetails =
        try SwiftPrebuiltExternalModuleDetails(compiledModulePath:
                                                TextualVirtualPath(path: VirtualPath.absolute(externalModulePath).intern()),
                                               isFramework: externalModuleDetails.isFramework)
        let newInfo = ModuleInfo(modulePath: TextualVirtualPath(path: VirtualPath.absolute(externalModulePath).intern()),
                                 sourceFiles: [],
                                 directDependencies: currentInfo.directDependencies,
                                 details: .swiftPrebuiltExternal(newExternalModuleDetails))
        Self.replaceModule(originalId: swiftModuleId, replacementId: prebuiltModuleId,
                           replacementInfo: newInfo, in: &modules)
      } else if let currentPrebuiltInfo = modules[prebuiltModuleId] {
        // Just update the isFramework bit on this prebuilt module dependency
        let newExternalModuleDetails =
        try SwiftPrebuiltExternalModuleDetails(compiledModulePath:
                                                TextualVirtualPath(path: VirtualPath.absolute(externalModulePath).intern()),
                                               isFramework: externalModuleDetails.isFramework)
        let newInfo = ModuleInfo(modulePath: TextualVirtualPath(path: VirtualPath.absolute(externalModulePath).intern()),
                                 sourceFiles: [],
                                 directDependencies: currentPrebuiltInfo.directDependencies,
                                 details: .swiftPrebuiltExternal(newExternalModuleDetails))
        Self.replaceModule(originalId: prebuiltModuleId, replacementId: prebuiltModuleId,
                           replacementInfo: newInfo, in: &modules)
      }
    }
  }
}

extension InterModuleDependencyGraph {
  var topologicalSorting: [ModuleDependencyId] {
    get throws {
      try topologicalSort(Array(modules.keys),
                          successors: {
        var dependencies: [ModuleDependencyId] = []
        let moduleInfo = try moduleInfo(of: $0)
        dependencies.append(contentsOf: moduleInfo.directDependencies ?? [])
        if case .swift(let swiftModuleDetails) = moduleInfo.details {
          dependencies.append(contentsOf: swiftModuleDetails.swiftOverlayDependencies ?? [])
        }
        return dependencies
      })
    }
  }

  /// Compute a set of modules that are "reachable" (form direct or transitive dependency)
  /// from each module in the graph.
  /// This routine relies on the fact that the dependency graph is acyclic. A lack of cycles means
  /// we can apply a simple algorithm:
  /// for each v ∈ V { T(v) = { v } }
  /// for v ∈ V in reverse topological order {
  ///   for each (v, w) ∈ E {
  ///     T(v) = T(v) ∪ T(w)
  ///   }
  /// }
  @_spi(Testing) public func computeTransitiveClosure() throws -> [ModuleDependencyId : Set<ModuleDependencyId>] {
    let topologicalIdList = try self.topologicalSorting
    // This structure will contain the final result
    var transitiveClosureMap =
      topologicalIdList.reduce(into: [ModuleDependencyId : Set<ModuleDependencyId>]()) {
        $0[$1] = [$1]
      }
    // Traverse the set of modules in reverse topological order, assimilating transitive closures
    for moduleId in topologicalIdList.reversed() {
      let moduleInfo = try moduleInfo(of: moduleId)
      for dependencyId in moduleInfo.directDependencies! {
        transitiveClosureMap[moduleId]!.formUnion(transitiveClosureMap[dependencyId]!)
      }
      // For Swift dependencies, their corresponding Swift Overlay dependencies
      // and bridging header dependencies are equivalent to direct dependencies.
      if case .swift(let swiftModuleDetails) = moduleInfo.details {
        let swiftOverlayDependencies = swiftModuleDetails.swiftOverlayDependencies ?? []
        for dependencyId in swiftOverlayDependencies {
          transitiveClosureMap[moduleId]!.formUnion(transitiveClosureMap[dependencyId]!)
        }
        let bridgingHeaderDependencies = swiftModuleDetails.bridgingHeaderDependencies ?? []
        for dependencyId in bridgingHeaderDependencies {
          transitiveClosureMap[moduleId]!.formUnion(transitiveClosureMap[dependencyId]!)
        }
      }
    }
    // For ease of use down-the-line, remove the node's self from its set of reachable nodes
    for (key, _) in transitiveClosureMap {
      transitiveClosureMap[key]!.remove(key)
    }
    return transitiveClosureMap
  }
}

@_spi(Testing) public extension InterModuleDependencyGraph {
  /// Merge a module with a given ID and Info into a ModuleInfoMap
  static func mergeModule(_ moduleId: ModuleDependencyId,
                          _ moduleInfo: ModuleInfo,
                          into moduleInfoMap: inout ModuleInfoMap) throws {
    switch moduleId {
      case .swift:
        let prebuiltExternalModuleEquivalentId =
          ModuleDependencyId.swiftPrebuiltExternal(moduleId.moduleName)
        let placeholderEquivalentId =
          ModuleDependencyId.swiftPlaceholder(moduleId.moduleName)
        if moduleInfoMap[prebuiltExternalModuleEquivalentId] != nil ||
            moduleInfoMap[moduleId] != nil {
          // If the set of discovered externalModules contains a .swiftPrebuiltExternal or .swift module
          // with the same name, do not replace it.
          break
        } else if moduleInfoMap[placeholderEquivalentId] != nil {
          // Replace the placeholder module with a full .swift ModuleInfo
          // and fixup other externalModules' dependencies
          replaceModule(originalId: placeholderEquivalentId, replacementId: moduleId,
                        replacementInfo: moduleInfo, in: &moduleInfoMap)
        } else {
          // Insert the new module
          moduleInfoMap[moduleId] = moduleInfo
        }

      case .swiftPrebuiltExternal:
        // If the set of discovered externalModules contains a .swift module with the same name,
        // replace it with the prebuilt version and fixup other externalModules' dependencies
        let swiftModuleEquivalentId = ModuleDependencyId.swift(moduleId.moduleName)
        let swiftPlaceholderEquivalentId = ModuleDependencyId.swiftPlaceholder(moduleId.moduleName)
        if moduleInfoMap[swiftModuleEquivalentId] != nil {
          // If the ModuleInfoMap contains an equivalent .swift module, replace it with the prebuilt
          // version and update all other externalModules' dependencies
          replaceModule(originalId: swiftModuleEquivalentId, replacementId: moduleId,
                        replacementInfo: moduleInfo, in: &moduleInfoMap)
        } else if moduleInfoMap[swiftPlaceholderEquivalentId] != nil {
          // If the moduleInfoMap contains an equivalent .swiftPlaceholder module, replace it with
          // the prebuilt version and update all other externalModules' dependencies
          replaceModule(originalId: swiftPlaceholderEquivalentId, replacementId: moduleId,
                        replacementInfo: moduleInfo, in: &moduleInfoMap)
        } else {
          // Insert the new module
          moduleInfoMap[moduleId] = moduleInfo
        }

      case .clang:
        guard let existingModuleInfo = moduleInfoMap[moduleId] else {
          moduleInfoMap[moduleId] = moduleInfo
          break
        }
        // If this module *has* been seen before, merge the module infos to capture
        // the super-set of so-far discovered dependencies of this module at various
        // PCMArg scanning actions.
        let combinedDependenciesInfo = mergeClangModuleInfoDependencies(moduleInfo,
                                                                        existingModuleInfo)
        replaceModule(originalId: moduleId, replacementId: moduleId,
                      replacementInfo: combinedDependenciesInfo, in: &moduleInfoMap)
      case .swiftPlaceholder:
        fatalError("Unresolved placeholder dependency at graph merge operation: \(moduleId)")
    }
  }

  /// Replace an existing module in the moduleInfoMap
  static func replaceModule(originalId: ModuleDependencyId, replacementId: ModuleDependencyId,
                            replacementInfo: ModuleInfo,
                            in moduleInfoMap: inout ModuleInfoMap) {
    precondition(moduleInfoMap[originalId] != nil)
    moduleInfoMap.removeValue(forKey: originalId)
    moduleInfoMap[replacementId] = replacementInfo
    if originalId != replacementId {
      updateDependencies(from: originalId, to: replacementId, in: &moduleInfoMap)
    }
  }

  /// Replace all references to the original module in other externalModules' dependencies with the new module.
  static func updateDependencies(from originalId: ModuleDependencyId,
                                 to replacementId: ModuleDependencyId,
                                 in moduleInfoMap: inout ModuleInfoMap) {
    for moduleId in moduleInfoMap.keys {
      var moduleInfo = moduleInfoMap[moduleId]!
      // Skip over placeholders, they do not have dependencies
      if case .swiftPlaceholder(_) = moduleId {
        continue
      }
      if let originalModuleIndex = moduleInfo.directDependencies?.firstIndex(of: originalId) {
        moduleInfo.directDependencies![originalModuleIndex] = replacementId;
        moduleInfoMap[moduleId] = moduleInfo
      }
    }
  }

  /// Given two moduleInfos of clang externalModules, merge them by combining their directDependencies and
  /// dependenciesCapturedPCMArgs and sourceFiles fields. These fields may differ across the same module
  /// scanned at different PCMArgs (e.g. -target option).
  static func mergeClangModuleInfoDependencies(_ firstInfo: ModuleInfo, _ secondInfo:ModuleInfo
  ) -> ModuleInfo {
    guard case .clang(let firstDetails) = firstInfo.details,
          case .clang(let secondDetails) = secondInfo.details
    else {
      fatalError("mergeClangModules expected two valid ClangModuleDetails objects.")
    }

    // As far as their dependencies go, these module infos are identical
    if firstInfo.directDependencies == secondInfo.directDependencies,
       firstDetails.capturedPCMArgs == secondDetails.capturedPCMArgs,
       firstInfo.sourceFiles == secondInfo.sourceFiles {
      return firstInfo
    }

    // Create a new moduleInfo that represents this module with combined dependency information
    let firstModuleSources = firstInfo.sourceFiles ?? []
    let secondModuleSources = secondInfo.sourceFiles ?? []
    let combinedSourceFiles = Array(Set(firstModuleSources + secondModuleSources))

    let firstModuleDependencies = firstInfo.directDependencies ?? []
    let secondModuleDependencies = secondInfo.directDependencies ?? []
    let combinedDependencies = Array(Set(firstModuleDependencies + secondModuleDependencies))

    let firstModuleCapturedPCMArgs = firstDetails.capturedPCMArgs ?? Set<[String]>()
    let secondModuleCapturedPCMArgs = secondDetails.capturedPCMArgs ?? Set<[String]>()
    let combinedCapturedPCMArgs = firstModuleCapturedPCMArgs.union(secondModuleCapturedPCMArgs)

    let combinedModuleDetails =
      ClangModuleDetails(moduleMapPath: firstDetails.moduleMapPath,
                         contextHash: firstDetails.contextHash,
                         commandLine: firstDetails.commandLine,
                         capturedPCMArgs: combinedCapturedPCMArgs)

    return ModuleInfo(modulePath: firstInfo.modulePath,
                      sourceFiles: combinedSourceFiles,
                      directDependencies: combinedDependencies,
                      details: .clang(combinedModuleDetails))
  }
}

internal extension InterModuleDependencyGraph {
  func explainDependency(dependencyModuleName: String) throws -> [[ModuleDependencyId]]? {
    guard modules.contains(where: { $0.key.moduleName == dependencyModuleName }) else { return nil }
    var results = Set<[ModuleDependencyId]>()
    try findAllPaths(source: .swift(mainModuleName),
                     to: dependencyModuleName,
                     pathSoFar: [.swift(mainModuleName)],
                     results: &results)
    return results.sorted(by: { $0.count < $1.count })
  }


  private func findAllPaths(source: ModuleDependencyId,
                            to moduleName: String,
                            pathSoFar: [ModuleDependencyId],
                            results: inout Set<[ModuleDependencyId]>) throws {
    let sourceInfo = try moduleInfo(of: source)
    // If the source is our target, we are done
    if source.moduleName == moduleName {
      // If the source is a target Swift module, also check if it
      // depends on a corresponding Clang module with the same name.
      // If it does, add it to the path as well.
      var completePath = pathSoFar
      if let dependencies = sourceInfo.directDependencies,
         dependencies.contains(.clang(moduleName)) {
        completePath.append(.clang(moduleName))
      }
      results.insert(completePath)
    }

    var allDependencies = sourceInfo.directDependencies ?? []
    if case .swift(let swiftModuleDetails) = sourceInfo.details,
          let overlayDependencies = swiftModuleDetails.swiftOverlayDependencies {
      allDependencies.append(contentsOf: overlayDependencies)
    }

    for dependency in allDependencies {
      try findAllPaths(source: dependency,
                       to: moduleName,
                       pathSoFar: pathSoFar + [dependency],
                       results: &results)
    }
  }
}
