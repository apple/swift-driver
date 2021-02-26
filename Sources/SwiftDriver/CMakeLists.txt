# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(SwiftDriver
  "ExplicitModuleBuilds/ClangVersionedDependencyResolution.swift"
  "ExplicitModuleBuilds/ExplicitDependencyBuildPlanner.swift"
  "ExplicitModuleBuilds/ModuleDependencyScanning.swift"
  "ExplicitModuleBuilds/PlaceholderDependencyResolution.swift"
  "ExplicitModuleBuilds/SerializableModuleArtifacts.swift"
  "ExplicitModuleBuilds/InterModuleDependencies/CommonDependencyOperations.swift"
  "ExplicitModuleBuilds/InterModuleDependencies/InterModuleDependencyGraph.swift"
  "ExplicitModuleBuilds/InterModuleDependencies/InterModuleDependencyOracle.swift"

  SwiftScan/DependencyGraphBuilder.swift
  SwiftScan/SwiftScan.swift

  Driver/CompilerMode.swift
  Driver/DebugInfo.swift
  Driver/Driver.swift
  Driver/LinkKind.swift
  Driver/ModuleOutputInfo.swift
  Driver/OutputFileMap.swift
  Driver/ToolExecutionDelegate.swift
  Driver/DriverVersion.swift

  Execution/ArgsResolver.swift
  Execution/DriverExecutor.swift
  Execution/ParsableOutput.swift
  Execution/ProcessProtocol.swift

  "IncrementalCompilation/ModuleDependencyGraphParts/Integrator.swift"
  "IncrementalCompilation/ModuleDependencyGraphParts/Node.swift"
  "IncrementalCompilation/ModuleDependencyGraphParts/NodeFinder.swift"
  "IncrementalCompilation/ModuleDependencyGraphParts/DependencySource.swift"
  "IncrementalCompilation/ModuleDependencyGraphParts/Tracer.swift"
  "IncrementalCompilation/BidirectionalMap.swift"
  "IncrementalCompilation/BuildRecord.swift"
  "IncrementalCompilation/BuildRecordInfo.swift"
  "IncrementalCompilation/DependencyGraphDotFileWriter.swift"
  "IncrementalCompilation/DependencyKey.swift"
  "IncrementalCompilation/DictionaryOfDictionaries.swift"
  "IncrementalCompilation/DirectAndTransitiveCollections.swift"
  "IncrementalCompilation/ExternalDependencyAndFingerprintEnforcer.swift"
  "IncrementalCompilation/IncrementalCompilationState.swift"
  "IncrementalCompilation/InitialStateComputer.swift"
  "IncrementalCompilation/InputInfo.swift"
  "IncrementalCompilation/KeyAndFingerprintHolder.swift"
  "IncrementalCompilation/ModuleDependencyGraph.swift"
  "IncrementalCompilation/Multidictionary.swift"
  "IncrementalCompilation/SourceFileDependencyGraph.swift"
  "IncrementalCompilation/TwoDMap.swift"

  Jobs/AutolinkExtractJob.swift
  Jobs/BackendJob.swift
  Jobs/CommandLineArguments.swift
  Jobs/CompileJob.swift
  Jobs/DarwinToolchain+LinkerSupport.swift
  Jobs/EmitModuleJob.swift
  Jobs/EmitSupportedFeaturesJob.swift
  Jobs/FrontendJobHelpers.swift
  Jobs/GenerateDSYMJob.swift
  Jobs/GeneratePCHJob.swift
  Jobs/GeneratePCMJob.swift
  Jobs/GenericUnixToolchain+LinkerSupport.swift
  Jobs/InterpretJob.swift
  Jobs/Job.swift
  Jobs/LinkJob.swift
  Jobs/MergeModuleJob.swift
  Jobs/ModuleWrapJob.swift
  Jobs/Planning.swift
  Jobs/PrintTargetInfoJob.swift
  Jobs/ReplJob.swift
  Jobs/Toolchain+InterpreterSupport.swift
  Jobs/Toolchain+LinkerSupport.swift
  Jobs/VerifyDebugInfoJob.swift
  Jobs/VerifyModuleInterfaceJob.swift
  Jobs/WindowsToolchain+LinkerSupport.swift
  Jobs/WebAssemblyToolchain+LinkerSupport.swift

  Toolchains/DarwinToolchain.swift
  Toolchains/GenericUnixToolchain.swift
  Toolchains/Toolchain.swift
  Toolchains/WindowsToolchain.swift
  Toolchains/WebAssemblyToolchain.swift

  Utilities/DOTJobGraphSerializer.swift
  Utilities/DateAdditions.swift
  Utilities/Diagnostics.swift
  Utilities/FileList.swift
  Utilities/FileType.swift
  Utilities/PredictableRandomNumberGenerator.swift
  Utilities/RelativePathAdditions.swift
  Utilities/Sanitizer.swift
  Utilities/StringAdditions.swift
  Utilities/System.swift
  Utilities/Triple+Platforms.swift
  Utilities/Triple.swift
  Utilities/TypedVirtualPath.swift
  Utilities/VersionExtensions.swift
  Utilities/VirtualPath.swift)

target_link_libraries(SwiftDriver PUBLIC
  TSCBasic
  TSCUtility
  SwiftOptions)
target_link_libraries(SwiftDriver PRIVATE
  CYaml
  Yams
  CSwiftScan)

set_property(GLOBAL APPEND PROPERTY SWIFTDRIVER_EXPORTS SwiftDriver)

# NOTE: workaround for CMake not setting up include flags yet
set_target_properties(SwiftDriver PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

install(TARGETS SwiftDriver
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)
