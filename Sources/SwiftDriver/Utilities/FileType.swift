//===--------------- FileType.swift - Swift File Types --------------------===//
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

/// Describes the kinds of files that the driver understands.
///
/// The raw values for these enumerations describe the default extension for
/// the file type.
public enum FileType: String, Hashable, CaseIterable, Codable {
  /// Swift source file.
  case swift

  /// (Canonical) SIL source file
  case sil

  /// (Canonical) SIB files
  case sib

  /// AST dump
  case ast

  /// An executable image.
  case image = "out"

  /// An object file.
  case object = "o"

  /// A dSYM directory.
  case dSYM

  /// A file containing make-style dependencies.
  case dependencies = "d"

  /// An autolink input file
  case autolink

  /// A compiled Swift module file.
  case swiftModule = "swiftmodule"

  /// Swift documentation for a module.
  case swiftDocumentation = "swiftdoc"

  /// A textual Swift interface file.
  case swiftInterface = "swiftinterface"

  /// An SPI Swift Interface file.
  case privateSwiftInterface = "private.swiftinterface"

  /// An interface file containng package decls as well as SPI and public decls.
  case packageSwiftInterface = "package.swiftinterface"

  /// Serialized source information.
  case swiftSourceInfoFile = "swiftsourceinfo"

  /// Extracted compile-time-known values
  case swiftConstValues = "swiftconstvalues"

  /// Assembler source.
  case assembly = "s"

  /// Raw SIL source file
  case raw_sil

  /// Raw sib file
  case raw_sib

  /// LLVM IR file
  case llvmIR = "ll"

  /// LLVM bitcode
  case llvmBitcode = "bc"

  /// Clang/Swift serialized diagnostics
  case diagnostics = "dia"

  /// Serialized diagnostics produced by module-generation
  case emitModuleDiagnostics = "emit-module.dia"

  /// Serialized diagnostics produced by module-generation
  case emitModuleDependencies = "emit-module.d"

  /// Objective-C header
  case objcHeader = "h"

  /// Swift dependencies file.
  case swiftDeps = "swiftdeps"

  /// Serialized dependency scanner state
  case modDepCache = "moddepcache"

  /// Remapping file
  case remap

  /// Imported modules.
  case importedModules = "importedmodules"

  /// Text-based dylib (TBD) file.
  case tbd

  /// JSON-based Module Dependency Scanner output
  case jsonDependencies = "dependencies.json"

  /// JSON-based -print-target-info output
  case jsonTargetInfo = "targetInfo.json"

  /// JSON-based -emit-supported-features output
  case jsonCompilerFeatures = "compilerFeatures.json"

  /// JSON-based binary Swift module artifact description
  case jsonSwiftArtifacts = "artifacts.json"

  /// Module trace file.
  ///
  /// Module traces are used by Apple's internal build infrastructure. Apple
  /// engineers can see more details on the "Swift module traces" page in the
  /// Swift section of the internal wiki.
  case moduleTrace = "trace.json"

  /// Indexing data directory
  ///
  /// The extension isn't real, rather this FileType specifies a directory path.
  case indexData

  /// Output path to record in the indexing data store
  ///
  /// This is only needed for use as a key in the output file map.
  case indexUnitOutputPath

  /// Optimization record
  case yamlOptimizationRecord = "opt.yaml"

  /// Bitstream optimization record
  case bitstreamOptimizationRecord = "opt.bitstream"

  /// Clang compiler module file
  case pcm

  /// Clang precompiled header
  case pch

  /// Clang Module Map
  case clangModuleMap = "modulemap"

  /// API baseline JSON
  case jsonAPIBaseline = "api.json"

  /// ABI baseline JSON
  case jsonABIBaseline = "abi.json"

  /// API descriptor JSON
  case jsonAPIDescriptor

  /// Swift Module Summary
  case moduleSummary = "swiftmodulesummary"

  /// Swift Module Semantic Info
  case moduleSemanticInfo

  /// Cached Diagnostics
  case cachedDiagnostics
}

extension FileType: CustomStringConvertible {
  public var description: String {
    switch self {
    case .swift, .sil, .sib, .image, .dSYM, .dependencies, .emitModuleDependencies,
         .autolink, .swiftModule, .swiftDocumentation, .swiftInterface,
         .swiftSourceInfoFile, .assembly, .remap, .tbd, .pcm, .pch,
         .clangModuleMap:
      return rawValue
    case .object:
      return "object"

    case .ast:
      return "ast-dump"

    case .raw_sil:
      return "raw-sil"

    case .raw_sib:
      return "raw-sib"

    case .llvmIR:
      return "llvm-ir"

    case .llvmBitcode:
      return "llvm-bc"

    case .privateSwiftInterface:
      return "private-swiftinterface"

    case .packageSwiftInterface:
      return "package-swiftinterface"

    case .objcHeader:
      return "objc-header"

    case .swiftDeps:
      return "swift-dependencies"

    case .modDepCache:
        return "dependency-scanner-cache"

    case .jsonDependencies:
      return "json-dependencies"

    case .jsonTargetInfo:
      return "json-target-info"

    case .jsonCompilerFeatures:
      return "json-supported-features"

    case .jsonSwiftArtifacts:
      return "json-module-artifacts"

    case .importedModules:
      return "imported-modules"

    case .moduleTrace:
      return "module-trace"

    case .indexData:
      return "index-data"

    case .indexUnitOutputPath:
      return "index-unit-output-path"

    case .yamlOptimizationRecord:
      return "yaml-opt-record"

    case .bitstreamOptimizationRecord:
      return "bitstream-opt-record"

    case .diagnostics:
      return "diagnostics"

    case .emitModuleDiagnostics:
      return "emit-module-diagnostics"

    case .jsonAPIBaseline:
      return "api-baseline-json"

    case .jsonABIBaseline:
      return "abi-baseline-json"

    case .swiftConstValues:
      return "const-values"

    case .jsonAPIDescriptor:
      return "api-descriptor-json"

    case .moduleSummary:
      return "swift-module-summary"

    case .moduleSemanticInfo:
      return "module-semantic-info"

    case .cachedDiagnostics:
      return "cached-diagnostics"
    }
  }
}

extension FileType {
  /// Whether a file of this type is an input to a Swift compilation, such as
  /// a Swift or SIL source file.
  public var isPartOfSwiftCompilation: Bool {
    switch self {
    case .swift, .raw_sil, .sil, .raw_sib, .sib:
      return true
    case .object, .pch, .ast, .llvmIR, .llvmBitcode, .assembly, .swiftModule,
         .importedModules, .indexData, .remap, .dSYM, .autolink, .dependencies,
         .emitModuleDependencies, .swiftDocumentation, .pcm, .diagnostics,
         .emitModuleDiagnostics, .objcHeader, .image, .swiftDeps, .moduleTrace,
         .tbd, .yamlOptimizationRecord, .bitstreamOptimizationRecord,
         .swiftInterface, .privateSwiftInterface, .packageSwiftInterface, .swiftSourceInfoFile,
         .jsonDependencies, .clangModuleMap, .jsonTargetInfo, .jsonCompilerFeatures,
         .jsonSwiftArtifacts, .indexUnitOutputPath, .modDepCache, .jsonAPIBaseline,
         .jsonABIBaseline, .swiftConstValues, .jsonAPIDescriptor,
         .moduleSummary, .moduleSemanticInfo, .cachedDiagnostics:
      return false
    }
  }
}

extension FileType {

  private static let typesByName = Dictionary(uniqueKeysWithValues: FileType.allCases.map { ($0.name, $0) })

  init?(name: String) {
    guard let type = Self.typesByName[name] else { return nil }

    self = type
  }

  /// The NAME values as specified in FileTypes.def
  var name: String {
    switch self {
    case .swift:
      return "swift"
    case .sil:
      return "sil"
    case .sib:
      return "sib"
    case .image:
      return "image"
    case .object:
      return "object"
    case .dSYM:
      return "dSYM"
    case .dependencies:
      return "dependencies"
    case .emitModuleDependencies:
      return "emit-module-dependencies"
    case .autolink:
      return "autolink"
    case .swiftModule:
      return "swiftmodule"
    case .swiftDocumentation:
      return "swiftdoc"
    case .swiftInterface:
      return "swiftinterface"
    case .privateSwiftInterface:
      return "private-swiftinterface"
    case .packageSwiftInterface:
      return "package-swiftinterface"
    case .swiftSourceInfoFile:
      return "swiftsourceinfo"
    case .clangModuleMap:
      return "modulemap"
    case .assembly:
      return "assembly"
    case .remap:
      return "remap"
    case .tbd:
      return "tbd"
    case .pcm:
      return "pcm"
    case .pch:
      return "pch"
    case .ast:
      return "ast-dump"
    case .raw_sil:
      return "raw-sil"
    case .raw_sib:
      return "raw-sib"
    case .llvmIR:
      return "llvm-ir"
    case .llvmBitcode:
      return "llvm-bc"
    case .objcHeader:
      return "objc-header"
    case .swiftDeps:
      return "swift-dependencies"
    case .modDepCache:
      return "dependency-scanner-cache"
    case .jsonDependencies:
      return "json-dependencies"
    case .jsonTargetInfo:
      return "json-target-info"
    case .jsonCompilerFeatures:
      return "json-supported-features"
    case .jsonSwiftArtifacts:
      return "json-module-artifacts"
    case .importedModules:
      return "imported-modules"
    case .moduleTrace:
      return "module-trace"
    case .indexData:
      return "index-data"
    case .yamlOptimizationRecord:
      return "yaml-opt-record"
    case .bitstreamOptimizationRecord:
      return "bitstream-opt-record"
    case .diagnostics:
      return "diagnostics"
    case .emitModuleDiagnostics:
      return "emit-module-diagnostics"
    case .indexUnitOutputPath:
      return "index-unit-output-path"
    case .jsonAPIBaseline:
      return "api-baseline-json"
    case .jsonABIBaseline:
      return "abi-baseline-json"
    case .swiftConstValues:
      return "const-values"
    case .jsonAPIDescriptor:
      return "api-descriptor-json"
    case .moduleSummary:
      return "swiftmodulesummary"
    case .moduleSemanticInfo:
      return "module-semantic-info"
    case .cachedDiagnostics:
      return "cached-diagnostics"
    }
  }
}

extension FileType {
  var isTextual: Bool {
    switch self {
    case .swift, .sil, .dependencies, .emitModuleDependencies, .assembly, .ast,
         .raw_sil, .llvmIR,.objcHeader, .autolink, .importedModules, .tbd,
         .moduleTrace, .yamlOptimizationRecord, .swiftInterface, .privateSwiftInterface, .packageSwiftInterface,
         .jsonDependencies, .clangModuleMap, .jsonCompilerFeatures, .jsonTargetInfo,
         .jsonSwiftArtifacts, .jsonAPIBaseline, .jsonABIBaseline, .swiftConstValues,
         .jsonAPIDescriptor, .moduleSummary, .moduleSemanticInfo, .cachedDiagnostics:
      return true
    case .image, .object, .dSYM, .pch, .sib, .raw_sib, .swiftModule,
         .swiftDocumentation, .swiftSourceInfoFile, .llvmBitcode, .diagnostics,
         .pcm, .swiftDeps, .remap, .indexData, .bitstreamOptimizationRecord,
         .indexUnitOutputPath, .modDepCache, .emitModuleDiagnostics:
      return false
    }
  }

  /// Returns true if the type is produced in the compiler after the LLVM passes.
  /// For those types the compiler produces multiple output files in multi-threaded compilation.
  var isAfterLLVM: Bool {
    switch self {
    case .assembly, .llvmIR, .llvmBitcode, .object:
      return true
    case .swift, .sil, .sib, .ast, .image, .dSYM, .dependencies, .emitModuleDependencies,
         .autolink, .swiftModule, .swiftDocumentation, .swiftInterface,
         .privateSwiftInterface, .packageSwiftInterface, .swiftSourceInfoFile, .raw_sil, .raw_sib,
         .diagnostics, .emitModuleDiagnostics, .objcHeader, .swiftDeps, .remap,
         .importedModules, .tbd, .moduleTrace, .indexData, .yamlOptimizationRecord,
         .modDepCache, .bitstreamOptimizationRecord, .pcm, .pch, .jsonDependencies,
         .clangModuleMap, .jsonCompilerFeatures, .jsonTargetInfo, .jsonSwiftArtifacts,
         .indexUnitOutputPath, .jsonAPIBaseline, .jsonABIBaseline, .swiftConstValues,
         .jsonAPIDescriptor, .moduleSummary, .moduleSemanticInfo, .cachedDiagnostics:
      return false
    }
  }

  /// Returns true if producing the file type requires running SILGen.
  var requiresSILGen: Bool {
    switch self {
    case .swift, .ast, .indexData, .indexUnitOutputPath, .jsonCompilerFeatures, .jsonTargetInfo:
      return false
    case .sil, .sib, .image, .object, .dSYM, .dependencies, .autolink, .swiftModule, .swiftDocumentation, .swiftInterface, .privateSwiftInterface, .packageSwiftInterface, .swiftSourceInfoFile, .swiftConstValues, .assembly, .raw_sil, .raw_sib, .llvmIR, .llvmBitcode, .diagnostics, .emitModuleDiagnostics, .emitModuleDependencies, .objcHeader, .swiftDeps, .modDepCache, .remap, .importedModules, .tbd, .jsonDependencies, .jsonSwiftArtifacts, .moduleTrace, .yamlOptimizationRecord, .bitstreamOptimizationRecord, .pcm, .pch, .clangModuleMap, .jsonAPIBaseline, .jsonABIBaseline, .jsonAPIDescriptor, .moduleSummary, .moduleSemanticInfo, .cachedDiagnostics:
      return true
    }
  }

  /// Returns true if the type can be cached as output.
  var supportCaching: Bool {
    switch self {
    case .diagnostics, .emitModuleDiagnostics, // diagnostics are cached using cached diagnostics.
         // Those are by-product from swift-driver and not considered outputs need caching.
         .jsonSwiftArtifacts, .remap, .indexUnitOutputPath, .modDepCache,
         // the remaining should not be an output from a caching swift job.
         .swift, .image, .dSYM, .importedModules, .clangModuleMap,
         .jsonCompilerFeatures, .jsonTargetInfo, .autolink:
      return false
    case .assembly, .llvmIR, .llvmBitcode, .object, .sil, .sib, .ast,
         .dependencies, .emitModuleDependencies, .swiftModule,
         .swiftDocumentation, .swiftInterface, .privateSwiftInterface, .packageSwiftInterface,
         .swiftSourceInfoFile, .raw_sil, .raw_sib, .objcHeader, .swiftDeps, .tbd,
         .moduleTrace, .indexData, .yamlOptimizationRecord,
         .bitstreamOptimizationRecord, .pcm, .pch, .jsonDependencies,
         .jsonAPIBaseline, .jsonABIBaseline, .swiftConstValues, .jsonAPIDescriptor,
         .moduleSummary, .moduleSemanticInfo, .cachedDiagnostics:
      return true
    }
  }
}
