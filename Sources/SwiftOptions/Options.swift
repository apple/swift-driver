//===--------------- Options.swift - Swift Driver Options -----------------===//
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
//
// NOTE: Generated file, do not edit!
//
// This file is generated from 'apple/swift:include/swift/Option/Options.td'.
// Please see README.md#rebuilding-optionsswift for details
//
//===----------------------------------------------------------------------===//

extension Option {
  public static let INPUT: Option = Option("<input>", .input, attributes: [.argumentIsPath])
  public static let HASHHASHHASH: Option = Option("-###", .flag, alias: Option.driverPrintJobs)
  public static let abi: Option = Option("-abi", .flag, attributes: [.noDriver], helpText: "Dumping ABI interface")
  public static let abi_: Option = Option("--abi", .flag, alias: Option.abi, attributes: [.noDriver], helpText: "Dumping ABI interface")
  public static let abortOnModuleFail: Option = Option("-abort-on-module-fail", .flag, attributes: [.noDriver], helpText: "Abort if a module failed to load")
  public static let abortOnModuleFail_: Option = Option("--abort-on-module-fail", .flag, alias: Option.abortOnModuleFail, attributes: [.noDriver], helpText: "Abort if a module failed to load")
  public static let accessNotesPathEQ: Option = Option("-access-notes-path=", .joined, alias: Option.accessNotesPath, attributes: [.frontend, .argumentIsPath])
  public static let accessNotesPath: Option = Option("-access-notes-path", .separate, attributes: [.frontend, .argumentIsPath], helpText: "Specify YAML file to override attributes on Swift declarations in this module")
  public static let aliasModuleNamesInModuleInterface: Option = Option("-alias-module-names-in-module-interface", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "When emitting a module interface, disambiguate modules using distinct alias names")
  public static let allowableClient: Option = Option("-allowable-client", .separate, attributes: [.frontend, .moduleInterface], metaVar: "<vers>", helpText: "Module names that are allowed to import this module")
  public static let alwaysCompileOutputFiles: Option = Option("-always-compile-output-files", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Always compile output files even it might not change the results")
  public static let analyzeRequirementMachine: Option = Option("-analyze-requirement-machine", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Print out requirement machine statistics at the end of the compilation job")
  public static let apiDiffDataDir: Option = Option("-api-diff-data-dir", .separate, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<path>", helpText: "Load platform and version specific API migration data files from <path>. Ignored if -api-diff-data-file is specified.")
  public static let apiDiffDataFile: Option = Option("-api-diff-data-file", .separate, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<path>", helpText: "API migration data is from <path>")
  public static let enableAppExtensionLibrary: Option = Option("-application-extension-library", .flag, attributes: [.frontend, .noInteractive], helpText: "Restrict code to those available for App Extension Libraries")
  public static let enableAppExtension: Option = Option("-application-extension", .flag, attributes: [.frontend, .noInteractive], helpText: "Restrict code to those available for App Extensions")
  public static let AssertConfig: Option = Option("-assert-config", .separate, attributes: [.frontend, .moduleInterface], helpText: "Specify the assert_configuration replacement. Possible values are Debug, Release, Unchecked, DisableReplacement.")
  public static let AssumeSingleThreaded: Option = Option("-assume-single-threaded", .flag, attributes: [.helpHidden, .frontend], helpText: "Assume that code will be executed in a single-threaded environment")
  public static let autolinkForceLoad: Option = Option("-autolink-force-load", .flag, attributes: [.helpHidden, .frontend, .moduleInterface], helpText: "Force ld to link against this module even if no symbols are used")
  public static let autolinkLibrary: Option = Option("-autolink-library", .separate, attributes: [.frontend, .noDriver], helpText: "Add dependent library")
  public static let avoidEmitModuleSourceInfo: Option = Option("-avoid-emit-module-source-info", .flag, attributes: [.noInteractive, .doesNotAffectIncrementalBuild], helpText: "don't emit Swift source info file")
  public static let avoidLocation: Option = Option("-avoid-location", .flag, attributes: [.noDriver], helpText: "Avoid serializing the file paths of SDK nodes.")
  public static let avoidLocation_: Option = Option("--avoid-location", .flag, alias: Option.avoidLocation, attributes: [.noDriver], helpText: "Avoid serializing the file paths of SDK nodes.")
  public static let avoidToolArgs: Option = Option("-avoid-tool-args", .flag, attributes: [.noDriver], helpText: "Avoid serializing the arguments for invoking the tool.")
  public static let avoidToolArgs_: Option = Option("--avoid-tool-args", .flag, alias: Option.avoidToolArgs, attributes: [.noDriver], helpText: "Avoid serializing the arguments for invoking the tool.")
  public static let backupModuleInterfacePathEQ: Option = Option("-backup-module-interface-path=", .joined, alias: Option.backupModuleInterfacePath, attributes: [.frontend, .noDriver, .cacheInvariant])
  public static let backupModuleInterfacePath: Option = Option("-backup-module-interface-path", .separate, attributes: [.frontend, .noDriver, .cacheInvariant], helpText: "Directory of module interfaces as backups to those from SDKs")
  public static let badFileDescriptorRetryCount: Option = Option("-bad-file-descriptor-retry-count", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Number of retrying opening a file if previous open returns a bad file descriptor error.")
  public static let baselineDir: Option = Option("-baseline-dir", .joinedOrSeparate, attributes: [.noDriver, .argumentIsPath], helpText: "The path to a directory containing baseline files: macos.json, iphoneos.json, appletvos.json, watchos.json, and iosmac.json")
  public static let baselinePath: Option = Option("-baseline-path", .joinedOrSeparate, attributes: [.noDriver, .argumentIsPath], helpText: "The path to the Json file that we should use as the baseline")
  public static let batchScanInputFile: Option = Option("-batch-scan-input-file", .separate, attributes: [.frontend, .noDriver], metaVar: "<path>", helpText: "Specify a JSON file containing modules to perform batch dependencies scanning")
  public static let BFEQ: Option = Option("-BF=", .joined, alias: Option.BF, attributes: [.noDriver])
  public static let BF: Option = Option("-BF", .joinedOrSeparate, attributes: [.noDriver, .argumentIsPath], helpText: "add a directory to the baseline framework search path")
  public static let BIEQ: Option = Option("-BI=", .joined, alias: Option.BI, attributes: [.noDriver])
  public static let BI: Option = Option("-BI", .joinedOrSeparate, attributes: [.noDriver, .argumentIsPath], helpText: "add a module for baseline input")
  public static let blockListFile: Option = Option("-blocklist-file", .separate, attributes: [.frontend, .noDriver], metaVar: "<path>", helpText: "The path to a blocklist configuration file")
  public static let breakageAllowlistPath: Option = Option("-breakage-allowlist-path", .joinedOrSeparate, attributes: [.noDriver, .argumentIsPath], helpText: "An allowlist of breakages to not complain about")
  public static let bridgingHeaderDirectoryForPrint: Option = Option("-bridging-header-directory-for-print", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<path>", helpText: "Directory for bridging header to be printed in compatibility header")
  public static let bridgingHeaderPchKey: Option = Option("-bridging-header-pch-key", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Cache Key for bridging header pch")
  public static let bsdk: Option = Option("-bsdk", .joinedOrSeparate, attributes: [.noDriver, .argumentIsPath], helpText: "path to the baseline SDK to import frameworks")
  public static let buildModuleFromParseableInterface: Option = Option("-build-module-from-parseable-interface", .flag, alias: Option.compileModuleFromInterface, attributes: [.helpHidden, .frontend, .noDriver], group: .modes)
  public static let bypassBatchModeChecks: Option = Option("-bypass-batch-mode-checks", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Bypass checks for batch-mode errors.")
  public static let bypassResilience: Option = Option("-bypass-resilience-checks", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Ignore all checks for module resilience.")
  public static let cacheCompileJob: Option = Option("-cache-compile-job", .flag, attributes: [.frontend], helpText: "Enable compiler caching")
  public static let cacheDisableReplay: Option = Option("-cache-disable-replay", .flag, attributes: [.frontend, .cacheInvariant], helpText: "Skip loading the compilation result from cache")
  public static let cacheReplayPrefixMap: Option = Option("-cache-replay-prefix-map", .separate, attributes: [.frontend, .noDriver, .cacheInvariant], metaVar: "<prefix=replacement>", helpText: "Remap paths when replaying outputs from cache")
  public static let candidateModuleFile: Option = Option("-candidate-module-file", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<path>", helpText: "Specify Swift module may be ready to use for an interface")
  public static let casBackendMode: Option = Option("-cas-backend-mode=", .joined, attributes: [.frontend, .noDriver], metaVar: "native|casid|verify", helpText: "CASBackendMode for output kind")
  public static let casBackend: Option = Option("-cas-backend", .flag, attributes: [.frontend, .noDriver], helpText: "Enable using CASBackend for object file output")
  public static let casEmitCasidFile: Option = Option("-cas-emit-casid-file", .flag, attributes: [.frontend, .noDriver], helpText: "Emit .casid file next to object file when CAS Backend is enabled")
  public static let casFs: Option = Option("-cas-fs", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<cas-id>", helpText: "Root CASID for CAS FileSystem")
  public static let casPath: Option = Option("-cas-path", .separate, attributes: [.frontend, .cacheInvariant], metaVar: "<path>", helpText: "Path to CAS")
  public static let casPluginOption: Option = Option("-cas-plugin-option", .separate, attributes: [.frontend], metaVar: "<name>=<option>", helpText: "Option pass to CAS Plugin")
  public static let casPluginPath: Option = Option("-cas-plugin-path", .separate, attributes: [.frontend], metaVar: "<path>", helpText: "Path to CAS Plugin")
  public static let checkApiAvailabilityOnly: Option = Option("-check-api-availability-only", .flag, attributes: [.helpHidden, .frontend, .noInteractive], helpText: "Deprecated, has no effect")
  public static let checkOnoneCompleteness: Option = Option("-check-onone-completeness", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Print errors if the compile OnoneSupport module is missing symbols")
  public static let checkedAsyncObjcBridging: Option = Option("-checked-async-objc-bridging=", .joined, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Control whether checked continuations are used when bridging async calls from Swift to ObjC: 'on', 'off' ")
  public static let clangBuildSessionFile: Option = Option("-clang-build-session-file", .separate, attributes: [.frontend, .argumentIsPath], helpText: "Use the last modification time of <file> as the underlying Clang build session timestamp")
  public static let clangHeaderExposeDecls: Option = Option("-clang-header-expose-decls=", .joined, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "all-public|has-expose-attr", helpText: "Which declarations should be exposed in the generated clang header.")
  public static let clangHeaderExposeModule: Option = Option("-clang-header-expose-module", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<imported-module-name>=<generated-header-name>", helpText: "Allow the compiler to assume that APIs from the specified module are exposed to C/C++/Objective-C in another generated header, so that APIs in the current module that depend on declarations from the specified module can be exposed in the generated header.")
  public static let clangIncludeTreeRoot: Option = Option("-clang-include-tree-root", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<cas-id>", helpText: "Clang Include Tree CASID")
  public static let clangScannerModuleCachePath: Option = Option("-clang-scanner-module-cache-path", .separate, attributes: [.frontend, .doesNotAffectIncrementalBuild, .argumentIsPath], helpText: "Specifies the Clang dependency scanner module cache path")
  public static let clangTarget: Option = Option("-clang-target", .separate, attributes: [.frontend], helpText: "Separately set the target we should use for internal Clang instance")
  public static let codeCompleteCallPatternHeuristics: Option = Option("-code-complete-call-pattern-heuristics", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Use heuristics to guess whether we want call pattern completions")
  public static let codeCompleteInitsInPostfixExpr: Option = Option("-code-complete-inits-in-postfix-expr", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Include initializers when completing a postfix expression")
  public static let colorDiagnostics: Option = Option("-color-diagnostics", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Print diagnostics in color")
  public static let compareToBaselinePath: Option = Option("-compare-to-baseline-path", .separate, attributes: [.noInteractive, .argumentIsPath], metaVar: "<path>", helpText: "Compare the built module to the baseline at <path> and diagnose breaking changes using the API digester")
  public static let compileModuleFromInterface: Option = Option("-compile-module-from-interface", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Treat the (single) input as a swiftinterface and produce a module", group: .modes)
  public static let compilerAssertions: Option = Option("-compiler-assertions", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild, .cacheInvariant], helpText: "Enable internal self-checks while compiling", group: .internalDebug)
  public static let compilerStyleDiags: Option = Option("-compiler-style-diags", .flag, attributes: [.noDriver], helpText: "Print compiler style diagnostics to stderr.")
  public static let compilerStyleDiags_: Option = Option("--compiler-style-diags", .flag, alias: Option.compilerStyleDiags, attributes: [.noDriver], helpText: "Print compiler style diagnostics to stderr.")
  public static let concurrencyModelEQ: Option = Option("-concurrency-model=", .joined, alias: Option.concurrencyModel, attributes: [.helpHidden, .frontend, .noDriver])
  public static let concurrencyModel: Option = Option("-concurrency-model", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "standard|task-to-thread", helpText: "Which concurrency model is used.  Defaults to standard.")
  public static let conditionalRuntimeRecords: Option = Option("-conditional-runtime-records", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Allow removal of runtime metadata records (public types, protocol conformances) based on whether they're used or unused")
  public static let constGatherProtocolsFile: Option = Option("-const-gather-protocols-file", .separate, attributes: [.frontend, .noDriver], metaVar: "<path>", helpText: "Specify a list of protocols for extraction of conformances' const values'")
  public static let continueBuildingAfterErrors: Option = Option("-continue-building-after-errors", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Continue building, even after errors are encountered")
  public static let coveragePrefixMap: Option = Option("-coverage-prefix-map", .separate, attributes: [.frontend], metaVar: "<prefix=replacement>", helpText: "Remap source paths in coverage info")
  public static let CrossModuleOptimization: Option = Option("-cross-module-optimization", .flag, attributes: [.helpHidden, .frontend], helpText: "Perform cross-module optimization")
  public static let crosscheckUnqualifiedLookup: Option = Option("-crosscheck-unqualified-lookup", .flag, attributes: [.frontend, .noDriver], helpText: "Compare legacy DeclContext- to ASTScope-based unqualified name lookup (for debugging)")
  public static let cxxInteropGettersSettersAsProperties: Option = Option("-cxx-interop-getters-setters-as-properties", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Import getters and setters as computed properties in Swift")
  public static let cxxInteropUseOpaquePointerForMoveonly: Option = Option("-cxx-interop-use-opaque-pointer-for-moveonly", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Testing flag that will be eliminated soon. Do not use.")
  public static let cxxInteroperabilityMode: Option = Option("-cxx-interoperability-mode=", .joined, attributes: [.frontend, .moduleInterface], helpText: "Enables C++ interoperability; pass 'default' to enable or 'off' to disable")
  public static let c: Option = Option("-c", .flag, alias: Option.emitObject, attributes: [.frontend, .noInteractive], group: .modes)
  public static let debugAssertAfterParse: Option = Option("-debug-assert-after-parse", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Force an assertion failure after parsing", group: .debugCrash)
  public static let debugAssertImmediately: Option = Option("-debug-assert-immediately", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Force an assertion failure immediately", group: .debugCrash)
  public static let debugConstraintsAttempt: Option = Option("-debug-constraints-attempt", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Debug the constraint solver at a given attempt")
  public static let debugConstraintsOnLineEQ: Option = Option("-debug-constraints-on-line=", .joined, alias: Option.debugConstraintsOnLine, attributes: [.helpHidden, .frontend, .noDriver])
  public static let debugConstraintsOnLine: Option = Option("-debug-constraints-on-line", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<line>", helpText: "Debug the constraint solver for expressions on <line>")
  public static let debugConstraints: Option = Option("-debug-constraints", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Debug the constraint-based type checker")
  public static let debugCrashAfterParse: Option = Option("-debug-crash-after-parse", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Force a crash after parsing", group: .debugCrash)
  public static let debugCrashImmediately: Option = Option("-debug-crash-immediately", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Force a crash immediately", group: .debugCrash)
  public static let debugCycles: Option = Option("-debug-cycles", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Print out debug dumps when cycles are detected in evaluation")
  public static let debugDiagnosticNames: Option = Option("-debug-diagnostic-names", .flag, attributes: [.helpHidden, .frontend, .doesNotAffectIncrementalBuild], helpText: "Include diagnostic names when printing")
  public static let debugEmitInvalidSwiftinterfaceSyntax: Option = Option("-debug-emit-invalid-swiftinterface-syntax", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Write an invalid declaration into swiftinterface files")
  public static let debugForbidTypecheckPrefix: Option = Option("-debug-forbid-typecheck-prefix", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Triggers llvm fatal_error if typechecker tries to typecheck a decl with the provided prefix name")
  public static let debugGenericSignatures: Option = Option("-debug-generic-signatures", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Debug generic signatures")
  public static let debugInfoFormat: Option = Option("-debug-info-format=", .joined, attributes: [.frontend], helpText: "Specify the debug info format type to either 'dwarf' or 'codeview'")
  public static let debugInfoStoreInvocation: Option = Option("-debug-info-store-invocation", .flag, attributes: [.frontend], helpText: "Emit the compiler invocation in the debug info.")
  public static let debugInverseRequirements: Option = Option("-debug-inverse-requirements", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Print real requirements in -debug_generic_signatures output")
  public static let debugMapping: Option = Option("-debug-mapping", .flag, attributes: [.noDriver], helpText: "Dumping information for debug purposes")
  public static let debugMapping_: Option = Option("--debug-mapping", .flag, alias: Option.debugMapping, attributes: [.noDriver], helpText: "Dumping information for debug purposes")
  public static let debugPrefixMap: Option = Option("-debug-prefix-map", .separate, attributes: [.frontend], metaVar: "<prefix=replacement>", helpText: "Remap source paths in debug info")
  public static let debugRequirementMachine: Option = Option("-debug-requirement-machine=", .joined, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Fine-grained debug output from the generics implementation")
  public static let debugTimeExpressionTypeChecking: Option = Option("-debug-time-expression-type-checking", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Dumps the time it takes to type-check each expression")
  public static let debugTimeFunctionBodies: Option = Option("-debug-time-function-bodies", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Dumps the time it takes to type-check each function body")
  public static let debuggerSupport: Option = Option("-debugger-support", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Process swift code as if running in the debugger")
  public static let debuggerTestingTransform: Option = Option("-debugger-testing-transform", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Instrument the code with calls to an intrinsic that record the expected values of local variables so they can be compared against the results from the debugger.")
  public static let defineAvailability: Option = Option("-define-availability", .separate, attributes: [.frontend, .noInteractive], metaVar: "<macro>", helpText: "Define an availability macro in the format 'macroName : iOS 13.0, macOS 10.15'")
  public static let dependencyScanCachePath: Option = Option("-dependency-scan-cache-path", .separate, attributes: [.frontend, .noDriver], helpText: "The path to output the dependency scanner's internal state.")
  public static let deprecatedIntegratedRepl: Option = Option("-deprecated-integrated-repl", .flag, attributes: [.frontend, .noBatch], group: .modes)
  public static let deserializeDiff: Option = Option("-deserialize-diff", .flag, attributes: [.noDriver], helpText: "Deserialize diff items in a JSON file")
  public static let deserializeDiff_: Option = Option("--deserialize-diff", .flag, alias: Option.deserializeDiff, attributes: [.noDriver], helpText: "Deserialize diff items in a JSON file")
  public static let deserializeSdk: Option = Option("-deserialize-sdk", .flag, attributes: [.noDriver], helpText: "Deserialize sdk digester in a JSON file")
  public static let deserializeSdk_: Option = Option("--deserialize-sdk", .flag, alias: Option.deserializeSdk, attributes: [.noDriver], helpText: "Deserialize sdk digester in a JSON file")
  public static let diagnoseSdk: Option = Option("-diagnose-sdk", .flag, attributes: [.noDriver], helpText: "Diagnose SDK content in JSON file")
  public static let diagnoseSdk_: Option = Option("--diagnose-sdk", .flag, alias: Option.diagnoseSdk, attributes: [.noDriver], helpText: "Diagnose SDK content in JSON file")
  public static let diagnosticDocumentationPath: Option = Option("-diagnostic-documentation-path", .separate, attributes: [.frontend, .noDriver, .cacheInvariant], metaVar: "<path>", helpText: "Path to diagnostic documentation resources")
  public static let diagnosticStyleEQ: Option = Option("-diagnostic-style=", .joined, alias: Option.diagnosticStyle, attributes: [.frontend, .doesNotAffectIncrementalBuild], metaVar: "<style>")
  public static let diagnosticStyle: Option = Option("-diagnostic-style", .separate, attributes: [.frontend, .doesNotAffectIncrementalBuild], metaVar: "<style>", helpText: "The formatting style used when printing diagnostics ('swift' or 'llvm')")
  public static let diagnosticsEditorMode: Option = Option("-diagnostics-editor-mode", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Diagnostics will be used in editor")
  public static let digesterBreakageAllowlistPath: Option = Option("-digester-breakage-allowlist-path", .separate, attributes: [.noInteractive, .argumentIsPath], metaVar: "<path>", helpText: "The path to a list of permitted breaking changes the API digester should ignore")
  public static let digesterMode: Option = Option("-digester-mode", .separate, attributes: [.noInteractive], metaVar: "<api|abi>", helpText: "Whether the API digester should run in API or ABI mode (defaults to API checking)")
  public static let directClangCc1ModuleBuild: Option = Option("-direct-clang-cc1-module-build", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Use the specified -Xcc options to build a PCM by using Clang frontend directly, bypassing the Clang driver")
  public static let disableAccessControl: Option = Option("-disable-access-control", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't respect access control restrictions")
  public static let disableActorDataRaceChecks: Option = Option("-disable-actor-data-race-checks", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Disable runtime checks for actor data races")
  public static let disableAliasModuleNamesInModuleInterface: Option = Option("-disable-alias-module-names-in-module-interface", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "When emitting a module interface, disable disambiguating modules using distinct alias names")
  public static let disableAllAutolinking: Option = Option("-disable-all-autolinking", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable all Swift autolink directives")
  public static let disableArcOpts: Option = Option("-disable-arc-opts", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't run SIL ARC optimization passes.")
  public static let disableAstVerifier: Option = Option("-disable-ast-verifier", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Do not run the AST verifier during compilation. NOTE: This lets the user override the default behavior on whether or not the ASTVerifier is run. The default behavior is to run the verifier when asserts are enabled and not run it when asserts are disabled. NOTE: Can not be used if enable-ast-verifier is used as well")
  public static let disableAutolinkFrameworks: Option = Option("-disable-autolink-frameworks", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable autolinking against all frameworks")
  public static let disableAutolinkFramework: Option = Option("-disable-autolink-framework", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable autolinking against the provided framework")
  public static let disableAutolinkLibrary: Option = Option("-disable-autolink-library", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable autolinking against the provided library")
  public static let disableAutolinkingRuntimeCompatibilityConcurrency: Option = Option("-disable-autolinking-runtime-compatibility-concurrency", .flag, attributes: [.frontend], helpText: "Do not use autolinking for the concurrency runtime compatibility library")
  public static let disableAutolinkingRuntimeCompatibilityDynamicReplacements: Option = Option("-disable-autolinking-runtime-compatibility-dynamic-replacements", .flag, attributes: [.frontend], helpText: "Do not use autolinking for the dynamic replacement runtime compatibility library")
  public static let disableAutolinkingRuntimeCompatibility: Option = Option("-disable-autolinking-runtime-compatibility", .flag, attributes: [.frontend], helpText: "Do not use autolinking for runtime compatibility libraries")
  public static let disableAvailabilityChecking: Option = Option("-disable-availability-checking", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable checking for potentially unavailable APIs")
  public static let disableBatchMode: Option = Option("-disable-batch-mode", .flag, attributes: [.helpHidden, .frontend, .noInteractive], helpText: "Disable combining frontend jobs into batches")
  public static let disableBridgingPch: Option = Option("-disable-bridging-pch", .flag, attributes: [.helpHidden], helpText: "Disable automatic generation of bridging PCH files")
  public static let disableBuildingInterface: Option = Option("-disable-building-interface", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disallow building binary module from textual interface")
  public static let disableClangSpi: Option = Option("-disable-clang-spi", .flag, attributes: [.frontend, .noDriver], helpText: "Don't import Clang SPIs as Swift SPIs")
  public static let disableClangTarget: Option = Option("-disable-clang-target", .flag, attributes: [], helpText: "Disable a separately specified target triple for Clang instance to use")
  public static let disableClangimporterSourceImport: Option = Option("-disable-clangimporter-source-import", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable ClangImporter and forward all requests straight the DWARF importer.")
  public static let disableCrossModuleOptimization: Option = Option("-disable-cmo", .flag, attributes: [.helpHidden, .frontend], helpText: "Disable cross-module optimization")
  public static let disableCollocateMetadataFunctions: Option = Option("-disable-collocate-metadata-functions", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable collocate metadata functions")
  public static let disableColocateTypeDescriptors: Option = Option("-disable-colocate-type-descriptors", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable colocate type descriptors")
  public static let disableConcreteTypeMetadataMangledNameAccessors: Option = Option("-disable-concrete-type-metadata-mangled-name-accessors", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable concrete type metadata access by mangled name")
  public static let disableConstraintSolverPerformanceHacks: Option = Option("-disable-constraint-solver-performance-hacks", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable all the hacks in the constraint solver")
  public static let disableCrossImportOverlaySearch: Option = Option("-disable-cross-import-overlay-search", .flag, attributes: [.frontend, .noDriver], helpText: "Disable searching for cross import overlay file")
  public static let disableCrossImportOverlays: Option = Option("-disable-cross-import-overlays", .flag, attributes: [.frontend, .noDriver], helpText: "Do not automatically import declared cross-import overlays.")
  public static let cxxInteropDisableRequirementAtImport: Option = Option("-disable-cxx-interop-requirement-at-import", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Do not require C++ interoperability to be enabled when importing a Swift module that enables C++ interoperability")
  public static let disableDebuggerShadowCopies: Option = Option("-disable-debugger-shadow-copies", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable debugger shadow copies of local variables.This option is only useful for testing the compiler.")
  public static let disableDeserializationRecovery: Option = Option("-disable-deserialization-recovery", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't attempt to recover from missing xrefs (etc) in swiftmodules")
  public static let disableDeserializationSafety: Option = Option("-disable-deserialization-safety", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't avoid reading potentially unsafe decls in swiftmodules")
  public static let disableDiagnosticPasses: Option = Option("-disable-diagnostic-passes", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't run diagnostic passes")
  public static let disableDynamicActorIsolation: Option = Option("-disable-dynamic-actor-isolation", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Disable dynamic actor isolation checks")
  public static let disableEmitGenericClassRoTList: Option = Option("-disable-emit-generic-class-ro_t-list", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable emission of a section with references to class_ro_t of generic class patterns")
  public static let disableExperimentalClangImporterDiagnostics: Option = Option("-disable-experimental-clang-importer-diagnostics", .flag, attributes: [.helpHidden, .frontend, .noDriver, .moduleInterface], helpText: "Disable experimental diagnostics when importing C, C++, and Objective-C libraries")
  public static let disableExperimentalLifetimeDependenceInference: Option = Option("-disable-experimental-lifetime-dependence-inference", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable experimental lifetime dependence inference")
  public static let disableExperimentalOpenedExistentialTypes: Option = Option("-disable-experimental-opened-existential-types", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable experimental support for implicitly opened existentials")
  public static let disableExperimentalParserRoundTrip: Option = Option("-disable-experimental-parser-round-trip", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable round trip through the new swift parser")
  public static let disableExperimentalStringProcessing: Option = Option("-disable-experimental-string-processing", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable experimental string processing")
  public static let disableFailOnError: Option = Option("-disable-fail-on-error", .flag, attributes: [.noDriver], helpText: "Don't exit with a nonzero status if errors are emitted")
  public static let disableFailOnError_: Option = Option("--disable-fail-on-error", .flag, alias: Option.disableFailOnError, attributes: [.noDriver], helpText: "Don't exit with a nonzero status if errors are emitted")
  public static let disableForceLoadSymbols: Option = Option("-disable-force-load-symbols", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable generation of all Swift _FORCE_LOAD symbols")
  public static let disableFragileResilientProtocolWitnesses: Option = Option("-disable-fragile-relative-protocol-tables", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable relative protocol witness tables")
  public static let disableGenericMetadataPrespecialization: Option = Option("-disable-generic-metadata-prespecialization", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Do not statically specialize metadata for generic types at types that are known to be used in source.")
  public static let disableImplicitBacktracingModuleImport: Option = Option("-disable-implicit-backtracing-module-import", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable the implicit import of the _Backtracing module.")
  public static let disableImplicitConcurrencyModuleImport: Option = Option("-disable-implicit-concurrency-module-import", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable the implicit import of the _Concurrency module.")
  public static let disableImplicitCxxModuleImport: Option = Option("-disable-implicit-cxx-module-import", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable the implicit import of the C++ Standard Library module.")
  public static let disableImplicitStringProcessingModuleImport: Option = Option("-disable-implicit-string-processing-module-import", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable the implicit import of the _StringProcessing module.")
  public static let disableImplicitSwiftModules: Option = Option("-disable-implicit-swift-modules", .flag, attributes: [.frontend, .noDriver], helpText: "Disable building Swift modules implicitly by the compiler")
  public static let disableImportPtrauthFieldFunctionPointers: Option = Option("-disable-import-ptrauth-field-function-pointers", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable import of custom ptrauth qualified field function pointers")
  public static let disableIncrementalImports: Option = Option("-disable-incremental-imports", .flag, attributes: [.frontend], helpText: "Disable cross-module incremental build metadata and driver scheduling for Swift modules")
  public static let disableIncrementalLlvmCodegeneration: Option = Option("-disable-incremental-llvm-codegen", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable incremental llvm code generation.")
  public static let disableInferPublicConcurrentValue: Option = Option("-disable-infer-public-sendable", .flag, attributes: [.frontend, .noDriver], helpText: "Disable inference of Sendable conformances for public structs and enums")
  public static let disableInterfaceLockfile: Option = Option("-disable-interface-lock", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't lock interface file when building module")
  public static let disableInvalidEphemeralnessAsError: Option = Option("-disable-invalid-ephemeralness-as-error", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Diagnose invalid ephemeral to non-ephemeral conversions as warnings")
  public static let disableLargeLoadableTypesReg2mem: Option = Option("-disable-large-loadable-types-reg2mem", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable large loadable types register to memory pass")
  public static let disableLayoutStringValueWitnessesInstantiation: Option = Option("-disable-layout-string-value-witnesses-instantiation", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable runtime instantiation of layout string value witnesses for generic types")
  public static let disableLayoutStringValueWitnesses: Option = Option("-disable-layout-string-value-witnesses", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable layout string based value witnesses")
  public static let disableLegacyTypeInfo: Option = Option("-disable-legacy-type-info", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Completely disable legacy type layout")
  public static let disableLifetimeDependenceDiagnostics: Option = Option("-disable-lifetime-dependence-diagnostics", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable lifetime dependence diagnostics for Nonescapable types.")
  public static let disableLlvmOptzns: Option = Option("-disable-llvm-optzns", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't run LLVM optimization passes")
  public static let disableLlvmValueNames: Option = Option("-disable-llvm-value-names", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't add names to local values in LLVM IR")
  public static let disableLlvmVerify: Option = Option("-disable-llvm-verify", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't run the LLVM IR verifier.")
  public static let disableMigratorFixits: Option = Option("-disable-migrator-fixits", .flag, attributes: [.frontend, .noInteractive], helpText: "Disable the Migrator phase which automatically applies fix-its")
  public static let disableModulesValidateSystemHeaders: Option = Option("-disable-modules-validate-system-headers", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable validating system headers in the Clang importer")
  public static let disableNamedLazyImportAsMemberLoading: Option = Option("-disable-named-lazy-import-as-member-loading", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Import all of a type's import-as-member globals together, as Swift 5.10 and earlier did; temporary workaround for modules that are sensitive to this change")
  public static let disableNamedLazyMemberLoading: Option = Option("-disable-named-lazy-member-loading", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable per-name lazy member loading (obsolete)")
  public static let disableNewLlvmPassManager: Option = Option("-disable-new-llvm-pass-manager", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable the new llvm pass manager")
  public static let disableNewOperatorLookup: Option = Option("-disable-new-operator-lookup", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable the new operator decl and precedencegroup lookup behavior")
  public static let disableNonfrozenEnumExhaustivityDiagnostics: Option = Option("-disable-nonfrozen-enum-exhaustivity-diagnostics", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Allow switches over non-frozen enums without catch-all cases")
  public static let disableNskeyedarchiverDiagnostics: Option = Option("-disable-nskeyedarchiver-diagnostics", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Allow classes with unstable mangled names to adopt NSCoding")
  public static let disableObjcAttrRequiresFoundationModule: Option = Option("-disable-objc-attr-requires-foundation-module", .flag, attributes: [.helpHidden, .frontend, .noDriver, .moduleInterface], helpText: "Disable requiring uses of @objc to require importing the Foundation module")
  public static let disableObjcInterop: Option = Option("-disable-objc-interop", .flag, attributes: [.helpHidden, .frontend, .noDriver, .moduleInterface], helpText: "Disable Objective-C interop code generation and config directives")
  public static let disableObjectiveCProtocolSymbolicReferences: Option = Option("-disable-objective-c-protocol-symbolic-references", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable objective-c protocol symbolic references")
  public static let disableOnlyOneDependencyFile: Option = Option("-disable-only-one-dependency-file", .flag, attributes: [.doesNotAffectIncrementalBuild], helpText: "Disables incremental build optimization that only produces one dependencies file")
  public static let disableOsChecks: Option = Option("-disable-os-checks", .flag, attributes: [.noDriver], helpText: "Skip OS related diagnostics")
  public static let disableOsChecks_: Option = Option("--disable-os-checks", .flag, alias: Option.disableOsChecks, attributes: [.noDriver], helpText: "Skip OS related diagnostics")
  public static let disableOssaCompleteLifetimes: Option = Option("-disable-ossa-complete-lifetimes", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Do not require linear OSSA lifetimes after SILGen")
  public static let disableOssaOpts: Option = Option("-disable-ossa-opts", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't run SIL OSSA optimization passes.")
  public static let disableOssaVerifyComplete: Option = Option("-disable-ossa-verify-complete", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Do not verify linear OSSA lifetimes after SILGen")
  public static let disablePlaygroundTransform: Option = Option("-disable-playground-transform", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable playground transformation")
  public static let disablePreallocatedInstantiationCaches: Option = Option("-disable-preallocated-instantiation-caches", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Avoid preallocating metadata instantiation caches in globals")
  public static let disablePreviousImplementationCallsInDynamicReplacements: Option = Option("-disable-previous-implementation-calls-in-dynamic-replacements", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable calling the previous implementation in dynamic replacements")
  public static let disablePrintMissingImportsInModuleInterface: Option = Option("-disable-print-missing-imports-in-module-interface", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable adding to the module interface imports used from API and missing from the sources")
  public static let disableReadonlyStaticObjects: Option = Option("-disable-readonly-static-objects", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Avoid allocating static objects in a read-only data section")
  public static let disableReflectionMetadata: Option = Option("-disable-reflection-metadata", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable emission of reflection metadata for nominal types")
  public static let disableReflectionNames: Option = Option("-disable-reflection-names", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable emission of names of stored properties and enum cases inreflection metadata")
  public static let disableStrictConcurrencyRegionBasedIsolation: Option = Option("-disable-region-based-isolation-with-strict-concurrency", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable region based isolation when running with strict concurrency enabled. Only enabled with asserts")
  public static let disableRelativeProtocolWitnessTables: Option = Option("-disable-relative-protocol-witness-tables", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable relative protocol witness tables")
  public static let disableRemoveDeprecatedCheck: Option = Option("-disable-remove-deprecated-check", .flag, attributes: [.noDriver], helpText: "Skip diagnosing removal of deprecated symbols")
  public static let disableRemoveDeprecatedCheck_: Option = Option("--disable-remove-deprecated-check", .flag, alias: Option.disableRemoveDeprecatedCheck, attributes: [.noDriver], helpText: "Skip diagnosing removal of deprecated symbols")
  public static let disableRequirementMachineConcreteContraction: Option = Option("-disable-requirement-machine-concrete-contraction", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable preprocessing pass to eliminate conformance requirements on generic parameters which are made concrete")
  public static let disableRequirementMachineLoopNormalization: Option = Option("-disable-requirement-machine-loop-normalization", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable stronger minimization algorithm, for debugging only")
  public static let disableRequirementMachineReuse: Option = Option("-disable-requirement-machine-reuse", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable re-use of requirement machines for minimization, for debugging only")
  public static let disableRoundTripDebugTypes: Option = Option("-disable-round-trip-debug-types", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disables verification of debug info mangling")
  public static let disableSandbox: Option = Option("-disable-sandbox", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Disable using the sandbox when executing subprocesses")
  public static let disableSendingArgsAndResultsWithRegionIsolation: Option = Option("-disable-sending-args-and-results-with-region-based-isolation", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable sending args and results when region based isolation is enabled. Only enabled with asserts")
  public static let disableSilOpaqueValues: Option = Option("-disable-sil-opaque-values", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable SIL Opaque Values")
  public static let disableSilOwnershipVerifier: Option = Option("-disable-sil-ownership-verifier", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Do not verify ownership invariants during SIL Verification ")
  public static let disableSilPartialApply: Option = Option("-disable-sil-partial-apply", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable use of partial_apply in SIL generation")
  public static let disableSilPerfOptzns: Option = Option("-disable-sil-perf-optzns", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't run SIL performance optimization passes")
  public static let disableStackProtector: Option = Option("-disable-stack-protector", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable the stack-protector")
  public static let disableStandardSubstitutionsInReflectionMangling: Option = Option("-disable-standard-substitutions-in-reflection-mangling", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable referencing stdlib symbols via mangled names in reflection mangling")
  public static let disableSubstSilFunctionTypes: Option = Option("-disable-subst-sil-function-types", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable substituted function types for SIL type lowering of function values")
  public static let disableSwiftBridgeAttr: Option = Option("-disable-swift-bridge-attr", .flag, attributes: [.helpHidden, .frontend], helpText: "Disable using the swift bridge attribute")
  public static let disableSwiftSpecificLlvmOptzns: Option = Option("-disable-swift-specific-llvm-optzns", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't run Swift specific LLVM optimization passes.")
  public static let disableSwift3ObjcInference: Option = Option("-disable-swift3-objc-inference", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Deprecated, has no effect")
  public static let disableTargetOsChecking: Option = Option("-disable-target-os-checking", .flag, attributes: [.frontend, .noDriver], helpText: "Disable checking the target OS of serialized modules")
  public static let disableTestableAttrRequiresTestableModule: Option = Option("-disable-testable-attr-requires-testable-module", .flag, attributes: [.frontend, .noDriver], helpText: "Disable checking of @testable")
  public static let disableTransferringArgsAndResultsWithRegionIsolation: Option = Option("-disable-transferring-args-and-results-with-region-based-isolation", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable transferring args and results when region based isolation is enabled. Only enabled with asserts")
  public static let disableTypeLayouts: Option = Option("-disable-type-layout", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable type layout based lowering")
  public static let disableTypoCorrection: Option = Option("-disable-typo-correction", .flag, attributes: [.frontend, .noDriver], helpText: "Disable typo correction")
  public static let disableVerifyExclusivity: Option = Option("-disable-verify-exclusivity", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable verification of access markers used to enforce exclusivity.")
  public static let disallowForwardingDriver: Option = Option("-disallow-use-new-driver", .flag, helpText: "Disable using new swift-driver")
  public static let downgradeTypecheckInterfaceError: Option = Option("-downgrade-typecheck-interface-error", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Downgrade error to warning when typechecking emitted module interfaces")
  public static let driverAlwaysRebuildDependents: Option = Option("-driver-always-rebuild-dependents", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Always rebuild dependents of files that have been modified", group: .internalDebug)
  public static let driverBatchCount: Option = Option("-driver-batch-count", .separate, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Use the given number of batch-mode partitions, rather than partitioning dynamically", group: .internalDebug)
  public static let driverBatchSeed: Option = Option("-driver-batch-seed", .separate, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Use the given seed value to randomize batch-mode partitions", group: .internalDebug)
  public static let driverBatchSizeLimit: Option = Option("-driver-batch-size-limit", .separate, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Use the given number as the upper limit on dynamic batch-mode partition size", group: .internalDebug)
  public static let driverEmitFineGrainedDependencyDotFileAfterEveryImport: Option = Option("-driver-emit-fine-grained-dependency-dot-file-after-every-import", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Emit dot files every time driver imports an fine-grained swiftdeps file.", group: .internalDebug)
  public static let driverFilelistThresholdEQ: Option = Option("-driver-filelist-threshold=", .joined, alias: Option.driverFilelistThreshold)
  public static let driverFilelistThreshold: Option = Option("-driver-filelist-threshold", .separate, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], metaVar: "<n>", helpText: "Pass input or output file names as filelists if there are more than <n>", group: .internalDebug)
  public static let driverForceResponseFiles: Option = Option("-driver-force-response-files", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Force the use of response files for testing", group: .internalDebug)
  public static let driverMode: Option = Option("--driver-mode=", .joined, attributes: [.helpHidden], helpText: "Set the driver mode to either 'swift' or 'swiftc'")
  public static let driverPrintActions: Option = Option("-driver-print-actions", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Dump list of actions to perform", group: .internalDebug)
  public static let driverPrintBindings: Option = Option("-driver-print-bindings", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Dump list of job inputs and outputs", group: .internalDebug)
  public static let driverPrintDerivedOutputFileMap: Option = Option("-driver-print-derived-output-file-map", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Dump the contents of the derived output file map", group: .internalDebug)
  public static let driverPrintGraphviz: Option = Option("-driver-print-graphviz", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Write the job graph as a graphviz file")
  public static let driverPrintJobs: Option = Option("-driver-print-jobs", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Dump list of jobs to execute", group: .internalDebug)
  public static let driverPrintOutputFileMap: Option = Option("-driver-print-output-file-map", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Dump the contents of the output file map", group: .internalDebug)
  public static let driverShowIncremental: Option = Option("-driver-show-incremental", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "With -v, dump information about why files are being rebuilt", group: .internalDebug)
  public static let driverShowJobLifecycle: Option = Option("-driver-show-job-lifecycle", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Show every step in the lifecycle of driver jobs", group: .internalDebug)
  public static let driverSkipExecution: Option = Option("-driver-skip-execution", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Skip execution of subtasks when performing compilation", group: .internalDebug)
  public static let driverTimeCompilation: Option = Option("-driver-time-compilation", .flag, attributes: [.noInteractive, .doesNotAffectIncrementalBuild], helpText: "Prints the total time it took to execute all compilation tasks")
  public static let driverUseFilelists: Option = Option("-driver-use-filelists", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Pass input files as filelists whenever possible", group: .internalDebug)
  public static let driverUseFrontendPath: Option = Option("-driver-use-frontend-path", .separate, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Use the given executable to perform compilations. Arguments can be passed as a ';' separated list", group: .internalDebug)
  public static let driverVerifyFineGrainedDependencyGraphAfterEveryImport: Option = Option("-driver-verify-fine-grained-dependency-graph-after-every-import", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Debug DriverGraph by verifying it after every import", group: .internalDebug)
  public static let driverWarnUnusedOptions: Option = Option("-driver-warn-unused-options", .flag, attributes: [.helpHidden], helpText: "Emit warnings for any provided options which are unused by the driver")
  public static let dumpApiPath: Option = Option("-dump-api-path", .separate, attributes: [.frontend, .noDriver, .cacheInvariant], helpText: "The path to output swift interface files for the compiled source files")
  public static let dumpAst: Option = Option("-dump-ast", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Parse and type-check input file(s) and dump AST(s)", group: .modes)
  public static let dumpClangDiagnostics: Option = Option("-dump-clang-diagnostics", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Dump Clang diagnostics to stderr")
  public static let dumpClangLookupTables: Option = Option("-dump-clang-lookup-tables", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Dump the importer's Swift-name-to-Clang-name lookup tables to stderr")
  public static let dumpInterfaceHash: Option = Option("-dump-interface-hash", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Parse input file(s) and dump interface token hash(es)", group: .modes)
  public static let dumpJit: Option = Option("-dump-jit", .joinedOrSeparate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Dump JIT contents")
  public static let dumpMacroExpansions: Option = Option("-dump-macro-expansions", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Dumps the results of each macro expansion")
  public static let dumpMigrationStatesDir: Option = Option("-dump-migration-states-dir", .separate, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<path>", helpText: "Dump the input text, output text, and states for migration to <path>")
  public static let dumpParse: Option = Option("-dump-parse", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Parse input file(s) and dump AST(s)", group: .modes)
  public static let dumpPcm: Option = Option("-dump-pcm", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Dump debugging information about a precompiled Clang module", group: .modes)
  public static let dumpRequirementMachine: Option = Option("-dump-requirement-machine", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enables dumping rewrite systems from the generics implementation")
  public static let dumpScopeMaps: Option = Option("-dump-scope-maps", .separate, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], metaVar: "<expanded-or-list-of-line:column>", helpText: "Parse and type-check input file(s) and dump the scope map(s)", group: .modes)
  public static let dumpSdk: Option = Option("-dump-sdk", .flag, attributes: [.noDriver], helpText: "Dump SDK content to JSON file")
  public static let dumpSdk_: Option = Option("--dump-sdk", .flag, alias: Option.dumpSdk, attributes: [.noDriver], helpText: "Dump SDK content to JSON file")
  public static let dumpTypeInfo: Option = Option("-dump-type-info", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Output YAML dump of fixed-size types from all imported modules", group: .modes)
  public static let dumpTypeRefinementContexts: Option = Option("-dump-type-refinement-contexts", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Type-check input file(s) and dump type refinement contexts(s)", group: .modes)
  public static let dumpTypeWitnessSystems: Option = Option("-dump-type-witness-systems", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enables dumping type witness systems from associated type inference")
  public static let dumpUsr: Option = Option("-dump-usr", .flag, attributes: [.frontend, .noInteractive], helpText: "Dump USR for each declaration reference")
  public static let dwarfVersion: Option = Option("-dwarf-version=", .joined, attributes: [.frontend], metaVar: "<version>", helpText: "DWARF debug info version to produce if requested")
  public static let D: Option = Option("-D", .joinedOrSeparate, attributes: [.frontend], helpText: "Marks a conditional compilation flag as true")
  public static let embedBitcodeMarker: Option = Option("-embed-bitcode-marker", .flag, attributes: [.frontend, .noInteractive], helpText: "Embed placeholder LLVM IR data as a marker")
  public static let embedBitcode: Option = Option("-embed-bitcode", .flag, attributes: [.frontend, .noInteractive], helpText: "Embed LLVM IR bitcode as data")
  public static let embedTbdForModule: Option = Option("-embed-tbd-for-module", .separate, attributes: [.frontend], helpText: "Embed symbols from the module in the emitted tbd file")
  public static let emitAbiDescriptorPath: Option = Option("-emit-abi-descriptor-path", .separate, attributes: [.frontend, .noDriver, .cacheInvariant], metaVar: "<path>", helpText: "Output the ABI descriptor of current module to <path>")
  public static let emitApiDescriptorPath: Option = Option("-emit-api-descriptor-path", .separate, attributes: [.frontend, .noInteractive, .argumentIsPath, .supplementaryOutput, .cacheInvariant], metaVar: "<path>", helpText: "Output a JSON file describing the module's API to <path>")
  public static let emitApiDescriptor: Option = Option("-emit-api-descriptor", .flag, attributes: [.noInteractive, .supplementaryOutput, .cacheInvariant], helpText: "Output a JSON file describing the module's API")
  public static let emitAssembly: Option = Option("-emit-assembly", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit assembly file(s) (-S)", group: .modes)
  public static let emitAst: Option = Option("-emit-ast", .flag, alias: Option.dumpAst, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild])
  public static let emitBc: Option = Option("-emit-bc", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit LLVM BC file(s)", group: .modes)
  public static let emitClangHeaderNonmodularIncludes: Option = Option("-emit-clang-header-nonmodular-includes", .flag, attributes: [.frontend, .noInteractive, .supplementaryOutput], helpText: "Augment emitted Objective-C header with textual imports for every included modular import")
  public static let emitClangHeaderPath: Option = Option("-emit-clang-header-path", .separate, alias: Option.emitObjcHeaderPath, attributes: [.frontend, .noInteractive, .argumentIsPath, .supplementaryOutput, .cacheInvariant], helpText: "Emit an Objective-C and C++ header file to <path>")
  public static let emitConstValuesPath: Option = Option("-emit-const-values-path", .separate, attributes: [.frontend, .noInteractive, .argumentIsPath, .supplementaryOutput, .cacheInvariant], metaVar: "<path>", helpText: "Emit the extracted compile-time known values to <path>")
  public static let emitConstValues: Option = Option("-emit-const-values", .flag, attributes: [.noInteractive, .supplementaryOutput])
  public static let emitDependenciesPath: Option = Option("-emit-dependencies-path", .separate, attributes: [.frontend, .noDriver, .cacheInvariant], metaVar: "<path>", helpText: "Output basic Make-compatible dependencies file to <path>")
  public static let emitDependencies: Option = Option("-emit-dependencies", .flag, attributes: [.frontend, .noInteractive, .supplementaryOutput], helpText: "Emit basic Make-compatible dependencies files")
  public static let emitDigesterBaselinePath: Option = Option("-emit-digester-baseline-path", .separate, attributes: [.noInteractive, .argumentIsPath, .supplementaryOutput], metaVar: "<path>", helpText: "Emit a baseline file for the module to <path> using the API digester")
  public static let emitDigesterBaseline: Option = Option("-emit-digester-baseline", .flag, attributes: [.noInteractive, .supplementaryOutput], helpText: "Emit a baseline file for the module using the API digester")
  public static let emitEmptyObjectFile: Option = Option("-emit-empty-object-file", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Produce a valid but dummy object file when building a library module")
  public static let emitExecutable: Option = Option("-emit-executable", .flag, attributes: [.noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit a linked executable", group: .modes)
  public static let emitExtensionBlockSymbols: Option = Option("-emit-extension-block-symbols", .flag, attributes: [.helpHidden, .frontend, .noInteractive, .supplementaryOutput], helpText: "Emit 'swift.extension' symbols for extensions to external types instead of directly associating members and conformances with the extended nominal when generating symbol graphs")
  public static let emitFineGrainedDependencySourcefileDotFiles: Option = Option("-emit-fine-grained-dependency-sourcefile-dot-files", .flag, attributes: [.helpHidden, .frontend], helpText: "Emit dot files for every source file.")
  public static let emitFixitsPath: Option = Option("-emit-fixits-path", .separate, attributes: [.frontend, .noDriver, .cacheInvariant], metaVar: "<path>", helpText: "Output compiler fixits as source edits to <path>")
  public static let emitImportedModules: Option = Option("-emit-imported-modules", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit a list of the imported modules", group: .modes)
  public static let emitIrgen: Option = Option("-emit-irgen", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit LLVM IR file(s) before LLVM optimizations", group: .modes)
  public static let emitIr: Option = Option("-emit-ir", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit LLVM IR file(s) after LLVM optimizations", group: .modes)
  public static let emitLibrary: Option = Option("-emit-library", .flag, attributes: [.noInteractive], helpText: "Emit a linked library", group: .modes)
  public static let emitLoadedModuleTracePathEQ: Option = Option("-emit-loaded-module-trace-path=", .joined, alias: Option.emitLoadedModuleTracePath, attributes: [.frontend, .noInteractive, .argumentIsPath, .supplementaryOutput, .cacheInvariant])
  public static let emitLoadedModuleTracePath: Option = Option("-emit-loaded-module-trace-path", .separate, attributes: [.frontend, .noInteractive, .argumentIsPath, .supplementaryOutput, .cacheInvariant], metaVar: "<path>", helpText: "Emit the loaded module trace JSON to <path>")
  public static let emitLoadedModuleTrace: Option = Option("-emit-loaded-module-trace", .flag, attributes: [.frontend, .noInteractive, .supplementaryOutput], helpText: "Emit a JSON file containing information about what modules were loaded")
  public static let emitMacroExpansionFiles: Option = Option("-emit-macro-expansion-files", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Specify when to emit macro expansion file: 'none', 'debug', or 'diagnostics'")
  public static let emitMigratedFilePath: Option = Option("-emit-migrated-file-path", .separate, attributes: [.frontend, .noDriver, .noInteractive, .doesNotAffectIncrementalBuild], metaVar: "<path>", helpText: "Emit the migrated source file to <path>")
  public static let emitModuleDependenciesPath: Option = Option("-emit-module-dependencies-path", .separate, attributes: [.argumentIsPath, .supplementaryOutput], metaVar: "<path>", helpText: "Emit a discovered dependencies file for the emit-module task to <path>")
  public static let emitModuleDocPath: Option = Option("-emit-module-doc-path", .separate, attributes: [.frontend, .noDriver, .cacheInvariant], metaVar: "<path>", helpText: "Output module documentation file <path>")
  public static let emitModuleDoc: Option = Option("-emit-module-doc", .flag, attributes: [.frontend, .noDriver], helpText: "Emit a module documentation file based on documentation comments")
  public static let emitModuleInterfacePath: Option = Option("-emit-module-interface-path", .separate, attributes: [.frontend, .noInteractive, .argumentIsPath, .supplementaryOutput, .cacheInvariant], metaVar: "<path>", helpText: "Output module interface file to <path>")
  public static let emitModuleInterface: Option = Option("-emit-module-interface", .flag, attributes: [.noInteractive, .supplementaryOutput], helpText: "Output module interface file")
  public static let emitModulePathEQ: Option = Option("-emit-module-path=", .joined, alias: Option.emitModulePath, attributes: [.frontend, .noInteractive, .argumentIsPath, .supplementaryOutput, .cacheInvariant])
  public static let emitModulePath: Option = Option("-emit-module-path", .separate, attributes: [.frontend, .noInteractive, .argumentIsPath, .supplementaryOutput, .cacheInvariant], metaVar: "<path>", helpText: "Emit an importable module to <path>")
  public static let emitModuleSemanticInfoPath: Option = Option("-emit-module-semantic-info-path", .separate, attributes: [.frontend, .noDriver, .cacheInvariant], metaVar: "<path>", helpText: "Output semantic info of current module to <path>")
  public static let emitModuleSeparatelyWMO: Option = Option("-emit-module-separately-wmo", .flag, attributes: [.helpHidden], helpText: "Emit module files as a distinct job in wmo builds")
  public static let emitModuleSerializeDiagnosticsPath: Option = Option("-emit-module-serialize-diagnostics-path", .separate, attributes: [.argumentIsPath, .supplementaryOutput], metaVar: "<path>", helpText: "Emit a serialized diagnostics file for the emit-module task to <path>")
  public static let emitModuleSourceInfoPath: Option = Option("-emit-module-source-info-path", .separate, attributes: [.frontend, .noInteractive, .argumentIsPath, .supplementaryOutput], metaVar: "<path>", helpText: "Output module source info file to <path>")
  public static let emitModuleSourceInfo: Option = Option("-emit-module-source-info", .flag, attributes: [.frontend, .noDriver], helpText: "Output module source info file")
  public static let emitModuleSummaryPath: Option = Option("-emit-module-summary-path", .separate, attributes: [.frontend, .noInteractive, .argumentIsPath, .supplementaryOutput, .cacheInvariant], metaVar: "<path>", helpText: "Output module summary file to <path>")
  public static let emitModuleSummary: Option = Option("-emit-module-summary", .flag, attributes: [.noInteractive, .supplementaryOutput], helpText: "Output module summary file")
  public static let emitModule: Option = Option("-emit-module", .flag, attributes: [.frontend, .noInteractive, .supplementaryOutput], helpText: "Emit an importable module")
  public static let emitObjcHeaderPath: Option = Option("-emit-objc-header-path", .separate, attributes: [.frontend, .noInteractive, .argumentIsPath, .supplementaryOutput, .cacheInvariant], metaVar: "<path>", helpText: "Emit an Objective-C header file to <path>")
  public static let emitObjcHeader: Option = Option("-emit-objc-header", .flag, attributes: [.frontend, .noInteractive, .supplementaryOutput], helpText: "Emit an Objective-C header file")
  public static let emitObject: Option = Option("-emit-object", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit object file(s) (-c)", group: .modes)
  public static let emitPackageModuleInterfacePath: Option = Option("-emit-package-module-interface-path", .separate, attributes: [.helpHidden, .frontend, .noInteractive, .argumentIsPath, .supplementaryOutput, .cacheInvariant], metaVar: "<path>", helpText: "Output package module interface file to <path>")
  public static let emitParseableModuleInterfacePath: Option = Option("-emit-parseable-module-interface-path", .separate, alias: Option.emitModuleInterfacePath, attributes: [.helpHidden, .frontend, .noInteractive, .argumentIsPath, .supplementaryOutput, .cacheInvariant])
  public static let emitParseableModuleInterface: Option = Option("-emit-parseable-module-interface", .flag, alias: Option.emitModuleInterface, attributes: [.helpHidden, .noInteractive, .supplementaryOutput])
  public static let emitParse: Option = Option("-emit-parse", .flag, alias: Option.dumpParse, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild])
  public static let emitPch: Option = Option("-emit-pch", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Emit PCH for imported Objective-C header file", group: .modes)
  public static let emitPcm: Option = Option("-emit-pcm", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit a precompiled Clang module from a module map", group: .modes)
  public static let emitPrivateModuleInterfacePath: Option = Option("-emit-private-module-interface-path", .separate, attributes: [.helpHidden, .frontend, .noInteractive, .argumentIsPath, .supplementaryOutput, .cacheInvariant], metaVar: "<path>", helpText: "Output private module interface file to <path>")
  public static let emitReferenceDependenciesPath: Option = Option("-emit-reference-dependencies-path", .separate, attributes: [.frontend, .noDriver, .cacheInvariant], metaVar: "<path>", helpText: "Output Swift-style dependencies file to <path>")
  public static let emitReferenceDependencies: Option = Option("-emit-reference-dependencies", .flag, attributes: [.frontend, .noDriver], helpText: "Emit a Swift-style dependencies file")
  public static let emitRemapFilePath: Option = Option("-emit-remap-file-path", .separate, attributes: [.frontend, .noDriver, .noInteractive, .doesNotAffectIncrementalBuild], metaVar: "<path>", helpText: "Emit the replacement map describing Swift Migrator changes to <path>")
  public static let emitSibgen: Option = Option("-emit-sibgen", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit serialized AST + raw SIL file(s)", group: .modes)
  public static let emitSib: Option = Option("-emit-sib", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit serialized AST + canonical SIL file(s)", group: .modes)
  public static let emitSilgen: Option = Option("-emit-silgen", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit raw SIL file(s)", group: .modes)
  public static let emitSil: Option = Option("-emit-sil", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit canonical SIL file(s)", group: .modes)
  public static let emitSortedSil: Option = Option("-emit-sorted-sil", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "When printing SIL, print out all sil entities sorted by name to ease diffing")
  public static let stackPromotionChecks: Option = Option("-emit-stack-promotion-checks", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Emit runtime checks for correct stack promotion of objects.")
  public static let emitSupportedFeatures: Option = Option("-emit-supported-features", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit a JSON file including all supported compiler features", group: .modes)
  public static let emitSymbolGraphDir: Option = Option("-emit-symbol-graph-dir", .separate, attributes: [.helpHidden, .frontend, .noInteractive, .argumentIsPath, .supplementaryOutput], metaVar: "<dir>", helpText: "Emit a symbol graph to directory <dir>")
  public static let emitSymbolGraph: Option = Option("-emit-symbol-graph", .flag, attributes: [.helpHidden, .frontend, .noInteractive, .supplementaryOutput], helpText: "Emit a symbol graph")
  public static let emitTbdPathEQ: Option = Option("-emit-tbd-path=", .joined, alias: Option.emitTbdPath, attributes: [.frontend, .noInteractive, .argumentIsPath, .supplementaryOutput, .cacheInvariant])
  public static let emitTbdPath: Option = Option("-emit-tbd-path", .separate, attributes: [.frontend, .noInteractive, .argumentIsPath, .supplementaryOutput, .cacheInvariant], metaVar: "<path>", helpText: "Emit the TBD file to <path>")
  public static let emitTbd: Option = Option("-emit-tbd", .flag, attributes: [.frontend, .noInteractive, .supplementaryOutput], helpText: "Emit a TBD file")
  public static let emitVerboseSil: Option = Option("-emit-verbose-sil", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Emit locations during SIL emission")
  public static let emptyAbiDescriptor: Option = Option("-empty-abi-descriptor", .flag, attributes: [.frontend, .noDriver], helpText: "Avoid printing actual module content into ABI descriptor file")
  public static let emptyBaseline: Option = Option("-empty-baseline", .flag, attributes: [.noDriver], helpText: "Use empty baseline for diagnostics")
  public static let emptyBaseline_: Option = Option("--empty-baseline", .flag, alias: Option.emptyBaseline, attributes: [.noDriver], helpText: "Use empty baseline for diagnostics")
  public static let enableAccessControl: Option = Option("-enable-access-control", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Respect access control restrictions")
  public static let enableActorDataRaceChecks: Option = Option("-enable-actor-data-race-checks", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Emit runtime checks for actor data races")
  public static let enableAnonymousContextMangledNames: Option = Option("-enable-anonymous-context-mangled-names", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable emission of mangled names in anonymous context descriptors")
  public static let enableAstVerifier: Option = Option("-enable-ast-verifier", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Run the AST verifier during compilation. NOTE: This lets the user override the default behavior on whether or not the ASTVerifier is run. The default behavior is to run the verifier when asserts are enabled and not run it when asserts are disabled. NOTE: Can not be used if disable-ast-verifier is used as well")
  public static let enableAutolinkingRuntimeCompatibilityBytecodeLayouts: Option = Option("-enable-autolinking-runtime-compatibility-bytecode-layouts", .flag, attributes: [.frontend], helpText: "Enable autolinking for the bytecode layouts runtime compatibility library")
  public static let enableBareSlashRegex: Option = Option("-enable-bare-slash-regex", .flag, attributes: [.frontend, .moduleInterface], helpText: "Enable the use of forward slash regular-expression literal syntax")
  public static let enableBatchMode: Option = Option("-enable-batch-mode", .flag, attributes: [.helpHidden, .frontend, .noInteractive], helpText: "Enable combining frontend jobs into batches")
  public static let enableBridgingPch: Option = Option("-enable-bridging-pch", .flag, attributes: [.helpHidden], helpText: "Enable automatic generation of bridging PCH files")
  public static let enableBuiltinModule: Option = Option("-enable-builtin-module", .flag, attributes: [.frontend, .moduleInterface], helpText: "Enables the explicit import of the Builtin module")
  public static let EnbaleCMOEverything: Option = Option("-enable-cmo-everything", .flag, attributes: [.helpHidden, .frontend], helpText: "Perform cross-module optimization on everything (all APIs). This is the same level of serialization as Embedded Swift.")
  public static let enableCollocateMetadataFunctions: Option = Option("-enable-collocate-metadata-functions", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable collocate metadata functions")
  public static let enableColocateTypeDescriptors: Option = Option("-enable-colocate-type-descriptors", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable colocate type descriptors")
  public static let copyPropagationStateEQ: Option = Option("-enable-copy-propagation=", .joined, attributes: [.frontend, .noDriver], metaVar: "true|requested-passes-only|false", helpText: "Whether to enable copy propagation")
  public static let enableCopyPropagation: Option = Option("-enable-copy-propagation", .flag, attributes: [.frontend, .noDriver], helpText: "Run SIL copy propagation with lexical lifetimes to shorten object lifetimes while preserving variable lifetimes.")
  public static let enableCrossImportOverlays: Option = Option("-enable-cross-import-overlays", .flag, attributes: [.frontend, .noDriver], helpText: "Automatically import declared cross-import overlays.")
  public static let EnbaleDefaultCMO: Option = Option("-enable-default-cmo", .flag, attributes: [.helpHidden, .frontend], helpText: "Perform conservative cross-module optimization")
  public static let enableDeserializationRecovery: Option = Option("-enable-deserialization-recovery", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Attempt to recover from missing xrefs (etc) in swiftmodules")
  public static let enableDeserializationSafety: Option = Option("-enable-deserialization-safety", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Avoid reading potentially unsafe decls in swiftmodules")
  public static let enableDestroyHoisting: Option = Option("-enable-destroy-hoisting=", .joined, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "true|false", helpText: "Whether to enable destroy hoisting")
  public static let enableDeterministicCheck: Option = Option("-enable-deterministic-check", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Check compiler output determinism by running it twice")
  public static let enableDynamicReplacementChaining: Option = Option("-enable-dynamic-replacement-chaining", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable chaining of dynamic replacements")
  public static let enableEmitGenericClassRoTList: Option = Option("-enable-emit-generic-class-ro_t-list", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable emission of a section with references to class_ro_t of generic class patterns")
  public static let enableExperimentalAdditiveArithmeticDerivation: Option = Option("-enable-experimental-additive-arithmetic-derivation", .flag, attributes: [.frontend], helpText: "Enable experimental 'AdditiveArithmetic' derived conformances")
  public static let enableAsyncDemotion: Option = Option("-enable-experimental-async-demotion", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enables an optimization pass to demote async functions.")
  public static let enableExperimentalAsyncTopLevel: Option = Option("-enable-experimental-async-top-level", .flag, attributes: [.helpHidden, .frontend, .noDriver, .moduleInterface], helpText: "Enable experimental concurrency in top-level code")
  public static let enableExperimentalConcisePoundFile: Option = Option("-enable-experimental-concise-pound-file", .flag, attributes: [.frontend, .moduleInterface], helpText: "Enable experimental concise '#file' identifier")
  public static let enableExperimentalConcurrency: Option = Option("-enable-experimental-concurrency", .flag, attributes: [.helpHidden, .frontend, .noDriver, .moduleInterface], helpText: "Enable experimental concurrency model")
  public static let enableExperimentalCxxInterop: Option = Option("-enable-experimental-cxx-interop", .flag, attributes: [.helpHidden, .frontend, .noDriver, .moduleInterface], helpText: "Enable experimental C++ interop code generation and config directives")
  public static let enableExperimentalDistributed: Option = Option("-enable-experimental-distributed", .flag, attributes: [.helpHidden, .frontend, .noDriver, .moduleInterface], helpText: "Enable experimental 'distributed' actors and functions")
  public static let enableExperimentalEagerClangModuleDiagnostics: Option = Option("-enable-experimental-eager-clang-module-diagnostics", .flag, attributes: [.helpHidden, .frontend, .noDriver, .moduleInterface], helpText: "Enable experimental eager diagnostics reporting on the importability of all referenced C, C++, and Objective-C libraries")
  public static let enableExperimentalFeature: Option = Option("-enable-experimental-feature", .separate, attributes: [.frontend, .moduleInterface], helpText: "Enable an experimental feature")
  public static let enableExperimentalFlowSensitiveConcurrentCaptures: Option = Option("-enable-experimental-flow-sensitive-concurrent-captures", .flag, attributes: [.helpHidden, .frontend, .noDriver, .moduleInterface], helpText: "Enable flow-sensitive concurrent captures")
  public static let enableExperimentalForwardModeDifferentiation: Option = Option("-enable-experimental-forward-mode-differentiation", .flag, attributes: [.frontend], helpText: "Enable experimental forward mode differentiation")
  public static let enableExperimentalLifetimeDependenceInference: Option = Option("-enable-experimental-lifetime-dependence-inference", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable experimental lifetime dependence inference")
  public static let enableExperimentalMoveOnly: Option = Option("-enable-experimental-move-only", .flag, attributes: [.helpHidden, .frontend, .noDriver, .moduleInterface], helpText: "Enable experimental move only")
  public static let enableExperimentalNamedOpaqueTypes: Option = Option("-enable-experimental-named-opaque-types", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable experimental support for named opaque result types")
  public static let enableExperimentalOpaqueTypeErasure: Option = Option("-enable-experimental-opaque-type-erasure", .flag, attributes: [.helpHidden, .frontend, .noDriver, .moduleInterface], helpText: "Type-erases opaque types that conform to @_typeEraser protocols")
  public static let enableExperimentalOpenedExistentialTypes: Option = Option("-enable-experimental-opened-existential-types", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable experimental support for implicitly opened existentials")
  public static let enableExperimentalPairwiseBuildBlock: Option = Option("-enable-experimental-pairwise-build-block", .flag, attributes: [.helpHidden, .frontend, .noDriver, .moduleInterface], helpText: "Enable experimental pairwise 'buildBlock' for result builders")
  public static let enableExperimentalStaticAssert: Option = Option("-enable-experimental-static-assert", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable experimental #assert")
  public static let enableExperimentalStringProcessing: Option = Option("-enable-experimental-string-processing", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable experimental string processing")
  public static let enableExplicitExistentialTypes: Option = Option("-enable-explicit-existential-types", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable experimental support for explicit existential types")
  public static let enableFragileResilientProtocolWitnesses: Option = Option("-enable-fragile-relative-protocol-tables", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable relative protocol witness tables")
  public static let enableImplicitBacktracingModuleImport: Option = Option("-enable-implicit-backtracing-module-import", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable the implicit import of the _Backtracing module.")
  public static let enableImplicitDynamic: Option = Option("-enable-implicit-dynamic", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Add 'dynamic' to all declarations")
  public static let enableIncrementalImports: Option = Option("-enable-incremental-imports", .flag, attributes: [.frontend], helpText: "Enable cross-module incremental build metadata and driver scheduling for Swift modules")
  public static let enableInferPublicConcurrentValue: Option = Option("-enable-infer-public-sendable", .flag, attributes: [.frontend, .noDriver], helpText: "Enable inference of Sendable conformances for public structs and enums")
  public static let enableInvalidEphemeralnessAsError: Option = Option("-enable-invalid-ephemeralness-as-error", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Diagnose invalid ephemeral to non-ephemeral conversions as errors")
  public static let enableLargeLoadableTypesReg2mem: Option = Option("-enable-large-loadable-types-reg2mem", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable large loadable types register to memory pass")
  public static let enableLayoutStringValueWitnessesInstantiation: Option = Option("-enable-layout-string-value-witnesses-instantiation", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable runtime instantiation of layout string value witnesses for generic types")
  public static let enableLayoutStringValueWitnesses: Option = Option("-enable-layout-string-value-witnesses", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable layout string based value witnesses")
  public static let enableLexicalLifetimes: Option = Option("-enable-lexical-lifetimes=", .joined, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "true|false", helpText: "Whether to enable lexical lifetimes")
  public static let enableLexicalLifetimesNoArg: Option = Option("-enable-lexical-lifetimes", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable lexical lifetimes")
  public static let enableLibraryEvolution: Option = Option("-enable-library-evolution", .flag, attributes: [.frontend, .moduleInterface], helpText: "Build the module to allow binary-compatible library evolution")
  public static let enableLifetimeDependenceDiagnostics: Option = Option("-enable-lifetime-dependence-diagnostics", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable lifetime dependence diagnostics for Nonescapable types.")
  public static let enableLlvmValueNames: Option = Option("-enable-llvm-value-names", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Add names to local values in LLVM IR")
  public static let enableLlvmVfe: Option = Option("-enable-llvm-vfe", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Use LLVM IR Virtual Function Elimination on Swift class virtual tables")
  public static let enableLlvmWme: Option = Option("-enable-llvm-wme", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Use LLVM IR Witness Method Elimination on Swift protocol witness tables")
  public static let enableMoveInoutStackProtector: Option = Option("-enable-move-inout-stack-protector", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable the stack protector by moving values to temporaries")
  public static let enableNewLlvmPassManager: Option = Option("-enable-new-llvm-pass-manager", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable the new llvm pass manager")
  public static let enableNewOperatorLookup: Option = Option("-enable-new-operator-lookup", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable the new operator decl and precedencegroup lookup behavior")
  public static let enableNonfrozenEnumExhaustivityDiagnostics: Option = Option("-enable-nonfrozen-enum-exhaustivity-diagnostics", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Diagnose switches over non-frozen enums without catch-all cases")
  public static let enableNskeyedarchiverDiagnostics: Option = Option("-enable-nskeyedarchiver-diagnostics", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Diagnose classes with unstable mangled names adopting NSCoding")
  public static let enableObjcAttrRequiresFoundationModule: Option = Option("-enable-objc-attr-requires-foundation-module", .flag, attributes: [.helpHidden, .frontend, .noDriver, .moduleInterface], helpText: "Enable requiring uses of @objc to require importing the Foundation module")
  public static let enableObjcInterop: Option = Option("-enable-objc-interop", .flag, attributes: [.helpHidden, .frontend, .noDriver, .moduleInterface], helpText: "Enable Objective-C interop code generation and config directives")
  public static let enableObjectiveCProtocolSymbolicReferences: Option = Option("-enable-objective-c-protocol-symbolic-references", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable objective-c protocol symbolic references")
  public static let enableOnlyOneDependencyFile: Option = Option("-enable-only-one-dependency-file", .flag, attributes: [.doesNotAffectIncrementalBuild], helpText: "Enables incremental build optimization that only produces one dependencies file")
  public static let enableOperatorDesignatedTypes: Option = Option("-enable-operator-designated-types", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable operator designated types")
  public static let enableOssaCompleteLifetimes: Option = Option("-enable-ossa-complete-lifetimes", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Require linear OSSA lifetimes after SILGen")
  public static let enableOssaModules: Option = Option("-enable-ossa-modules", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Always serialize SIL in ossa form. If this flag is not passed in, when optimizing ownership will be lowered before serializing SIL")
  public static let enableOssaVerifyComplete: Option = Option("-enable-ossa-verify-complete", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Verify linear OSSA lifetimes after SILGen")
  public static let enablePackMetadataStackPromotion: Option = Option("-enable-pack-metadata-stack-promotion=", .joined, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "true|false", helpText: "Whether to skip heapifying stack metadata packs when possible.")
  public static let enablePackMetadataStackPromotionNoArg: Option = Option("-enable-pack-metadata-stack-promotion", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Skip heapifying stack metadata packs when possible.")
  public static let enablePrivateImports: Option = Option("-enable-private-imports", .flag, attributes: [.helpHidden, .frontend, .noInteractive], helpText: "Allows this module's internal and private API to be accessed")
  public static let enableRelativeProtocolWitnessTables: Option = Option("-enable-relative-protocol-witness-tables", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable relative protocol witness tables")
  public static let enableRemoveDeprecatedCheck: Option = Option("-enable-remove-deprecated-check", .flag, attributes: [.noDriver], helpText: "Diagnosing removal of deprecated symbols")
  public static let enableRemoveDeprecatedCheck_: Option = Option("--enable-remove-deprecated-check", .flag, alias: Option.enableRemoveDeprecatedCheck, attributes: [.noDriver], helpText: "Diagnosing removal of deprecated symbols")
  public static let enableRequirementMachineOpaqueArchetypes: Option = Option("-enable-requirement-machine-opaque-archetypes", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable more correct opaque archetype support, which is off by default because it might fail to produce a convergent rewrite system")
  public static let enableResilience: Option = Option("-enable-resilience", .flag, attributes: [.helpHidden, .frontend, .noDriver, .moduleInterface], helpText: "Deprecated, use -enable-library-evolution instead")
  public static let enableRoundTripDebugTypes: Option = Option("-enable-round-trip-debug-types", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enables verification of debug info mangling")
  public static let enableSilOpaqueValues: Option = Option("-enable-sil-opaque-values", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable SIL Opaque Values")
  public static let enableSingleModuleLlvmEmission: Option = Option("-enable-single-module-llvm-emission", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Emit LLVM IR into a single LLVM module in multithreaded mode.")
  public static let enableSourceImport: Option = Option("-enable-source-import", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable importing of Swift source files")
  public static let enableSpecDevirt: Option = Option("-enable-spec-devirt", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable speculative devirtualization pass.")
  public static let enableStackProtector: Option = Option("-enable-stack-protector", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable the stack protector")
  public static let enableSwift3ObjcInference: Option = Option("-enable-swift3-objc-inference", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Deprecated, has no effect")
  public static let enableTargetOsChecking: Option = Option("-enable-target-os-checking", .flag, attributes: [.frontend, .noDriver], helpText: "Enable checking the target OS of serialized modules")
  public static let enableTestableAttrRequiresTestableModule: Option = Option("-enable-testable-attr-requires-testable-module", .flag, attributes: [.frontend, .noDriver], helpText: "Enable checking of @testable")
  public static let enableTesting: Option = Option("-enable-testing", .flag, attributes: [.helpHidden, .frontend, .noInteractive], helpText: "Allows this module's internal API to be accessed for testing")
  public static let enableThrowWithoutTry: Option = Option("-enable-throw-without-try", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Allow throwing function calls without 'try'")
  public static let enableTypeLayouts: Option = Option("-enable-type-layout", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable type layout based lowering")
  public static let enableUpcomingFeature: Option = Option("-enable-upcoming-feature", .separate, attributes: [.frontend, .moduleInterface], helpText: "Enable a feature that will be introduced in an upcoming language version")
  public static let enableVerifyExclusivity: Option = Option("-enable-verify-exclusivity", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable verification of access markers used to enforce exclusivity.")
  public static let enableVolatileModules: Option = Option("-enable-volatile-modules", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Load Swift modules in memory")
  public static let enforceExclusivityEQ: Option = Option("-enforce-exclusivity=", .joined, attributes: [.frontend, .moduleInterface], metaVar: "<enforcement>", helpText: "Enforce law of exclusivity")
  public static let entryPointFunctionName: Option = Option("-entry-point-function-name", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<string>", helpText: "Name of the entry point function")
  public static let experimentalAllowModuleWithCompilerErrors: Option = Option("-experimental-allow-module-with-compiler-errors", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Attempt to output .swiftmodule, regardless of compilation errors")
  public static let experimentalAllowNonResilientAccess: Option = Option("-experimental-allow-non-resilient-access", .flag, attributes: [.frontend], helpText: "Allow non-resilient access by generating all contents besides exportable decls")
  public static let experimentalAllowedReexportedModules: Option = Option("-experimental-allowed-reexported-modules=", .commaJoined, attributes: [.noDriver], helpText: "Allow reexporting symbols from the provided modules if they are themselves exported from the main module. This is a comma separated list of module names.")
  public static let experimentalCForeignReferenceTypes: Option = Option("-experimental-c-foreign-reference-types", .flag, attributes: [.helpHidden, .frontend, .moduleInterface], helpText: "Enable experimental C foreign references types (with reference counting).")
  public static let experimentalClangImporterDirectCc1Scan: Option = Option("-experimental-clang-importer-direct-cc1-scan", .flag, attributes: [.helpHidden, .frontend], helpText: "Enables swift driver to construct swift-frontend invocations using -direct-clang-cc1-module-build")
  public static let experimentalCxxStdlib: Option = Option("-experimental-cxx-stdlib", .separate, attributes: [.helpHidden], helpText: "C++ standard library to use; forwarded to Clang's -stdlib flag")
  public static let emitModuleSeparately: Option = Option("-experimental-emit-module-separately", .flag, attributes: [.helpHidden], helpText: "Emit module files as a distinct job")
  public static let driverExperimentalExplicitModuleBuild: Option = Option("-experimental-explicit-module-build", .flag, alias: Option.driverExplicitModuleBuild, attributes: [.helpHidden], helpText: "Prebuild module dependencies to make them explicit")
  public static let forceWorkaroundBrokenModules: Option = Option("-experimental-force-workaround-broken-modules", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Attempt unsafe recovery for imported modules with broken modularization")
  public static let experimentalHermeticSealAtLink: Option = Option("-experimental-hermetic-seal-at-link", .flag, attributes: [.helpHidden, .frontend], helpText: "Library code can assume that all clients are visible at linktime, and aggressively strip unused code")
  public static let experimentalLazyTypecheck: Option = Option("-experimental-lazy-typecheck", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Type-check lazily as needed to produce requested outputs")
  public static let experimentalOneWayClosureParams: Option = Option("-experimental-one-way-closure-params", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable experimental support for one-way closure parameters")
  public static let experimentalPackageBypassResilience: Option = Option("-experimental-package-bypass-resilience", .flag, attributes: [.frontend], helpText: "Enable optimization to bypass resilience within a package")
  public static let ExperimentalPackageCMO: Option = Option("-experimental-package-cmo", .flag, attributes: [.frontend], helpText: "Enable optimization to perform default CMO within a package boundary")
  public static let experimentalPackageInterfaceLoad: Option = Option("-experimental-package-interface-load", .flag, attributes: [.helpHidden, .frontend], helpText: "Enables loading a package interface if in the same package specified with package-name")
  public static let ExperimentalPerformanceAnnotations: Option = Option("-experimental-performance-annotations", .flag, attributes: [.helpHidden, .frontend], helpText: "Deprecated, has no effect")
  public static let platformCCallingConventionEQ: Option = Option("-experimental-platform-c-calling-convention=", .joined, alias: Option.platformCCallingConvention, attributes: [.helpHidden, .frontend, .noDriver])
  public static let platformCCallingConvention: Option = Option("-experimental-platform-c-calling-convention", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Which calling convention is used to perform non-swift calls. Defaults to llvm's standard C calling convention.")
  public static let experimentalPrintFullConvention: Option = Option("-experimental-print-full-convention", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "When emitting a module interface or SIL, emit additional @convention arguments, regardless of whether they were written in the source. Also requires -use-clang-function-types to be enabled.")
  public static let experimentalSkipAllFunctionBodies: Option = Option("-experimental-skip-all-function-bodies", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Skip type-checking function bodies and all SIL generation")
  public static let experimentalSkipNonExportableDecls: Option = Option("-experimental-skip-non-exportable-decls", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Skip decls that are not exported to clients")
  public static let experimentalSkipNonInlinableFunctionBodiesWithoutTypes: Option = Option("-experimental-skip-non-inlinable-function-bodies-without-types", .flag, attributes: [.helpHidden, .frontend], helpText: "Skip work on non-inlinable function bodies that do not declare nested types")
  public static let experimentalSkipNonInlinableFunctionBodies: Option = Option("-experimental-skip-non-inlinable-function-bodies", .flag, attributes: [.helpHidden, .frontend], helpText: "Skip type-checking and SIL generation for non-inlinable function bodies")
  public static let experimentalSpiImports: Option = Option("-experimental-spi-imports", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable experimental support for SPI imports")
  public static let experimentalSpiOnlyImports: Option = Option("-experimental-spi-only-imports", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Enable use of @_spiOnly imports")
  public static let enableExperimentalSwiftBasedClosureSpecialization: Option = Option("-experimental-swift-based-closure-specialization", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Use the experimental Swift based closure-specialization optimization pass instead of the existing C++ one")
  public static let explainModuleDependency: Option = Option("-explain-module-dependency", .separate, attributes: [], helpText: "Emit remark/notes describing why compilation may depend on a module with a given name.")
  public static let explicitAutoLinking: Option = Option("-explicit-auto-linking", .flag, attributes: [], helpText: "Instead of linker-load directives, have the driver specify all link dependencies on the linker invocation. Requires '-explicit-module-build'.")
  public static let explicitDependencyGraphFormat: Option = Option("-explicit-dependency-graph-format=", .joined, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Specify the explicit dependency graph output format to either 'json' or 'dot'")
  public static let explicitInterfaceModuleBuild: Option = Option("-explicit-interface-module-build", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Use the specified command-line to build the module from interface, instead of flags specified in the interface")
  public static let driverExplicitModuleBuild: Option = Option("-explicit-module-build", .flag, attributes: [.helpHidden], helpText: "Prebuild module dependencies to make them explicit")
  public static let explicitSwiftModuleMap: Option = Option("-explicit-swift-module-map-file", .separate, attributes: [.frontend, .noDriver], metaVar: "<path>", helpText: "Specify a JSON file containing information of explicit Swift modules")
  public static let exportAs: Option = Option("-export-as", .separate, attributes: [.frontend, .moduleInterface], helpText: "Module name to use when referenced in clients module interfaces")
  public static let externalPassPipelineFilename: Option = Option("-external-pass-pipeline-filename", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<pass_pipeline_file>", helpText: "Use the pass pipeline defined by <pass_pipeline_file>")
  public static let externalPluginPath: Option = Option("-external-plugin-path", .separate, attributes: [.frontend, .argumentIsPath], metaVar: "<path>#<plugin-server-path>", helpText: "Add directory to the plugin search path with a plugin server executable", group: .pluginSearch)
  public static let e: Option = Option("-e", .separate, attributes: [], helpText: "Executes a line of code provided on the command line")
  public static let FEQ: Option = Option("-F=", .joined, alias: Option.F, attributes: [.frontend, .argumentIsPath])
  public static let fileCompilationDir: Option = Option("-file-compilation-dir", .separate, attributes: [.frontend], metaVar: "<path>", helpText: "The compilation directory to embed in the debug info. Coverage mapping is not supported yet.")
  public static let filePrefixMap: Option = Option("-file-prefix-map", .separate, attributes: [.frontend], metaVar: "<prefix=replacement>", helpText: "Remap source paths in debug, coverage, and index info")
  public static let filelist: Option = Option("-filelist", .separate, attributes: [.frontend, .noDriver, .argumentIsFileList], helpText: "Specify source inputs in a file rather than on the command line")
  public static let findUsr: Option = Option("-find-usr", .flag, attributes: [.noDriver], helpText: "Find USR for decls by given condition")
  public static let findUsr_: Option = Option("--find-usr", .flag, alias: Option.findUsr, attributes: [.noDriver], helpText: "Find USR for decls by given condition")
  public static let fixitAll: Option = Option("-fixit-all", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Apply all fixits from diagnostics without any filtering")
  public static let forcePublicLinkage: Option = Option("-force-public-linkage", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Force public linkage for private symbols. Used by LLDB.")
  public static let forceSingleFrontendInvocation: Option = Option("-force-single-frontend-invocation", .flag, alias: Option.wholeModuleOptimization, attributes: [.helpHidden, .frontend, .noInteractive])
  public static let forceStructTypeLayouts: Option = Option("-force-struct-type-layouts", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Force type layout based lowering for structs")
  public static let framework: Option = Option("-framework", .separate, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Specifies a framework which should be linked against", group: .linkerOption)
  public static let frontendParseableOutput: Option = Option("-frontend-parseable-output", .flag, attributes: [.frontend, .noDriver, .cacheInvariant], helpText: "Emit textual output in a parseable format")
  public static let Fsystem: Option = Option("-Fsystem", .separate, attributes: [.frontend, .argumentIsPath], helpText: "Add directory to system framework search path")
  public static let functionSections: Option = Option("-function-sections", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Emit functions to separate sections.")
  public static let F: Option = Option("-F", .joinedOrSeparate, attributes: [.frontend, .argumentIsPath], helpText: "Add directory to framework search path")
  public static let gccToolchain: Option = Option("-gcc-toolchain", .separate, attributes: [.helpHidden, .argumentIsPath], metaVar: "<path>", helpText: "Specify a directory where the clang importer and clang linker can find headers and libraries")
  public static let gdwarfTypes: Option = Option("-gdwarf-types", .flag, attributes: [.frontend], helpText: "Emit full DWARF type info.", group: .g)
  public static let generateEmptyBaseline: Option = Option("-generate-empty-baseline", .flag, attributes: [.noDriver], helpText: "Generate an empty baseline")
  public static let generateEmptyBaseline_: Option = Option("--generate-empty-baseline", .flag, alias: Option.generateEmptyBaseline, attributes: [.noDriver], helpText: "Generate an empty baseline")
  public static let generateMigrationScript: Option = Option("-generate-migration-script", .flag, attributes: [.noDriver], helpText: "Compare SDK content in JSON file and generate migration script")
  public static let generateMigrationScript_: Option = Option("--generate-migration-script", .flag, alias: Option.generateMigrationScript, attributes: [.noDriver], helpText: "Compare SDK content in JSON file and generate migration script")
  public static let generateNameCorrection: Option = Option("-generate-name-correction", .flag, attributes: [.noDriver], helpText: "Generate name correction template")
  public static let generateNameCorrection_: Option = Option("--generate-name-correction", .flag, alias: Option.generateNameCorrection, attributes: [.noDriver], helpText: "Generate name correction template")
  public static let glineTablesOnly: Option = Option("-gline-tables-only", .flag, attributes: [.frontend], helpText: "Emit minimal debug info for backtraces only", group: .g)
  public static let gnone: Option = Option("-gnone", .flag, attributes: [.frontend], helpText: "Don't emit debug info", group: .g)
  public static let groupInfoPath: Option = Option("-group-info-path", .separate, attributes: [.frontend, .noDriver, .cacheInvariant], helpText: "The path to collect the group information of the compiled module")
  public static let legacyGsil: Option = Option("-gsil", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Deprecated, use '-sil-based-debuginfo' instead")
  public static let g: Option = Option("-g", .flag, attributes: [.frontend], helpText: "Emit debug info. This is the preferred setting for debugging with LLDB.", group: .g)
  public static let helpHidden: Option = Option("-help-hidden", .flag, attributes: [.helpHidden, .frontend], helpText: "Display available options, including hidden options")
  public static let helpHidden_: Option = Option("--help-hidden", .flag, alias: Option.helpHidden, attributes: [.helpHidden, .frontend], helpText: "Display available options, including hidden options")
  public static let help: Option = Option("-help", .flag, attributes: [.frontend, .autolinkExtract, .moduleWrap, .indent], helpText: "Display available options")
  public static let help_: Option = Option("--help", .flag, alias: Option.help, attributes: [.frontend, .autolinkExtract, .moduleWrap, .indent], helpText: "Display available options")
  public static let h: Option = Option("-h", .flag, alias: Option.help)
  public static let IEQ: Option = Option("-I=", .joined, alias: Option.I, attributes: [.frontend, .argumentIsPath])
  public static let iframework: Option = Option("-iframework", .joinedOrSeparate, attributes: [.noDriver, .argumentIsPath], helpText: "add a directory to the clang importer system framework search path")
  public static let ignoreAlwaysInline: Option = Option("-ignore-always-inline", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Ignore @inline(__always) attributes.")
  public static let ignoreModuleSourceInfo: Option = Option("-ignore-module-source-info", .flag, attributes: [.frontend, .noDriver], helpText: "Avoid getting source location from .swiftsourceinfo files")
  public static let ignoreSpiGroups: Option = Option("-ignore-spi-group", .separate, attributes: [.noDriver], helpText: "SPI group name to not diagnose about")
  public static let ignoreSpiGroups_: Option = Option("--ignore-spi-group", .separate, alias: Option.ignoreSpiGroups, attributes: [.noDriver], helpText: "SPI group name to not diagnose about")
  public static let ignoredUsrs: Option = Option("-ignored-usrs", .separate, attributes: [.noDriver, .argumentIsPath], metaVar: "<path>", helpText: "the file containing USRs of removed decls that the digester should ignore")
  public static let ignoredUsrs_: Option = Option("--ignored-usrs", .separate, alias: Option.ignoredUsrs, attributes: [.noDriver, .argumentIsPath], metaVar: "<path>", helpText: "the file containing USRs of removed decls that the digester should ignore")
  public static let importBridgingHeader: Option = Option("-import-bridging-header", .separate, alias: Option.importObjcHeader, attributes: [.helpHidden, .frontend, .argumentIsPath])
  public static let importCfTypes: Option = Option("-import-cf-types", .flag, attributes: [.helpHidden, .frontend], helpText: "Recognize and import CF types as class types")
  public static let importModule: Option = Option("-import-module", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Implicitly import the specified module")
  public static let importObjcHeader: Option = Option("-import-objc-header", .separate, attributes: [.helpHidden, .frontend, .argumentIsPath], helpText: "Implicitly imports an Objective-C header file")
  public static let importPrescan: Option = Option("-import-prescan", .flag, attributes: [.frontend, .noDriver], helpText: "When performing a dependency scan, only identify all imports of the main Swift module sources")
  public static let importUnderlyingModule: Option = Option("-import-underlying-module", .flag, attributes: [.frontend, .noInteractive], helpText: "Implicitly imports the Objective-C half of a module")
  public static let inPlace: Option = Option("-in-place", .flag, attributes: [.noInteractive, .noBatch, .indent], helpText: "Overwrite input file with formatted file.", group: .codeFormatting)
  public static let inProcessPluginServerPath: Option = Option("-in-process-plugin-server-path", .separate, attributes: [.frontend, .argumentIsPath], helpText: "Path to dynamic library plugin server")
  public static let includeSpiSymbols: Option = Option("-include-spi-symbols", .flag, attributes: [.helpHidden, .frontend, .noInteractive, .supplementaryOutput], helpText: "Add symbols with SPI information to the symbol graph")
  public static let incremental: Option = Option("-incremental", .flag, attributes: [.helpHidden, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Perform an incremental build if possible")
  public static let indentSwitchCase: Option = Option("-indent-switch-case", .flag, attributes: [.noInteractive, .noBatch, .indent], helpText: "Indent cases in switch statements.", group: .codeFormatting)
  public static let indentWidth: Option = Option("-indent-width", .separate, attributes: [.noInteractive, .noBatch, .indent], metaVar: "<n>", helpText: "Number of characters to indent.", group: .codeFormatting)
  public static let indexFilePath: Option = Option("-index-file-path", .separate, attributes: [.noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<path>", helpText: "Produce index data for file <path>")
  public static let indexFile: Option = Option("-index-file", .flag, attributes: [.noInteractive, .doesNotAffectIncrementalBuild], helpText: "Produce index data for a source file", group: .modes)
  public static let indexIgnoreClangModules: Option = Option("-index-ignore-clang-modules", .flag, attributes: [.frontend], helpText: "Avoid indexing clang modules (pcms)")
  public static let indexIgnoreStdlib: Option = Option("-index-ignore-stdlib", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Avoid emitting index data for the standard library.")
  public static let indexIgnoreSystemModules: Option = Option("-index-ignore-system-modules", .flag, attributes: [.noInteractive], helpText: "Avoid indexing system modules")
  public static let indexIncludeLocals: Option = Option("-index-include-locals", .flag, attributes: [.frontend], helpText: "Include local definitions/references in the produced index data.")
  public static let indexStorePath: Option = Option("-index-store-path", .separate, attributes: [.frontend, .argumentIsPath, .cacheInvariant], metaVar: "<path>", helpText: "Store indexing data to <path>")
  public static let indexSystemModules: Option = Option("-index-system-modules", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Emit index data for imported serialized swift system modules")
  public static let indexUnitOutputPathFilelist: Option = Option("-index-unit-output-path-filelist", .separate, attributes: [.frontend, .noDriver, .cacheInvariant], helpText: "Specify index unit output paths in a file rather than on the command line")
  public static let indexUnitOutputPath: Option = Option("-index-unit-output-path", .separate, attributes: [.frontend, .argumentIsPath, .cacheInvariant], metaVar: "<path>", helpText: "Use <path> as the output path in the produced index data.")
  public static let inputFileKey: Option = Option("-input-file-key", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Cache Key for input file")
  public static let inputPaths: Option = Option("-input-paths", .separate, attributes: [.noDriver, .argumentIsPath], metaVar: "<path>", helpText: "The SDK contents under comparison")
  public static let inputPaths_: Option = Option("--input-paths", .separate, alias: Option.inputPaths, attributes: [.noDriver, .argumentIsPath], metaVar: "<path>", helpText: "The SDK contents under comparison")
  public static let internalizeAtLink: Option = Option("-internalize-at-link", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Allow internalizing public symbols and vtables at link time (assume all client code of public types is part of the same link unit, or that external symbols are explicitly requested via -exported_symbols_list)")
  public static let interpret: Option = Option("-interpret", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Immediate mode", group: .modes)
  public static let I: Option = Option("-I", .joinedOrSeparate, attributes: [.frontend, .argumentIsPath], helpText: "Add directory to the import search path")
  public static let i: Option = Option("-i", .flag, group: .modes)
  public static let json: Option = Option("-json", .flag, attributes: [.noDriver], helpText: "Print output in JSON format.")
  public static let json_: Option = Option("--json", .flag, alias: Option.json, attributes: [.noDriver], helpText: "Print output in JSON format.")
  public static let j: Option = Option("-j", .joinedOrSeparate, attributes: [.doesNotAffectIncrementalBuild], metaVar: "<n>", helpText: "Number of commands to execute in parallel")
  public static let LEQ: Option = Option("-L=", .joined, alias: Option.L, attributes: [.frontend, .doesNotAffectIncrementalBuild, .argumentIsPath], group: .linkerOption)
  public static let ldPath: Option = Option("-ld-path=", .joined, attributes: [.helpHidden, .doesNotAffectIncrementalBuild, .argumentIsPath], helpText: "Specifies the path to the linker to be used")
  public static let libc: Option = Option("-libc", .separate, attributes: [], helpText: "libc runtime library to use")
  public static let libraryLevelEQ: Option = Option("-library-level=", .joined, alias: Option.libraryLevel, attributes: [.helpHidden, .frontend, .moduleInterface], metaVar: "<level>")
  public static let libraryLevel: Option = Option("-library-level", .separate, attributes: [.helpHidden, .frontend, .moduleInterface], metaVar: "<level>", helpText: "Library distribution level 'api', 'spi' or 'other' (the default)")
  public static let lineRange: Option = Option("-line-range", .separate, attributes: [.noInteractive, .noBatch, .indent], metaVar: "<n:n>", helpText: "<start line>:<end line>. Formats a range of lines (1-based). Can only be used with one input file.", group: .codeFormatting)
  public static let linkObjcRuntime: Option = Option("-link-objc-runtime", .flag, attributes: [.doesNotAffectIncrementalBuild], helpText: "Deprecated")
  public static let lldbRepl: Option = Option("-lldb-repl", .flag, attributes: [.helpHidden, .noBatch], helpText: "LLDB-enhanced REPL mode", group: .modes)
  public static let reuseDependencyScanCache: Option = Option("-load-dependency-scan-cache", .flag, attributes: [.frontend, .noDriver], helpText: "After performing a dependency scan, serialize the scanner's internal state.")
  public static let loadPluginExecutable: Option = Option("-load-plugin-executable", .separate, attributes: [.frontend, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<path>#<module-names>", helpText: "Path to a compiler plugin executable and a comma-separated list of module names where the macro types are declared", group: .pluginSearch)
  public static let loadPluginLibrary: Option = Option("-load-plugin-library", .separate, attributes: [.frontend, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<path>", helpText: "Path to a dynamic library containing compiler plugins such as macros", group: .pluginSearch)
  public static let locale: Option = Option("-locale", .separate, attributes: [.frontend, .doesNotAffectIncrementalBuild], metaVar: "<locale-code>", helpText: "Choose a language for diagnostic messages")
  public static let localizationPath: Option = Option("-localization-path", .separate, attributes: [.frontend, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<path>", helpText: "Path to localized diagnostic messages directory")
  public static let location: Option = Option("-location", .separate, attributes: [.noDriver], metaVar: "<location>", helpText: "Filter nodes with the given location.")
  public static let location_: Option = Option("--location", .separate, alias: Option.location, attributes: [.noDriver], metaVar: "<location>", helpText: "Filter nodes with the given location.")
  public static let ltoLibrary: Option = Option("-lto-library", .separate, attributes: [.frontend, .noInteractive, .argumentIsPath], metaVar: "<lto-library>", helpText: "Perform LTO with <lto-library>")
  public static let lto: Option = Option("-lto=", .joined, attributes: [.frontend, .noInteractive], helpText: "Specify the LTO type to either 'llvm-thin' or 'llvm-full'")
  public static let L: Option = Option("-L", .joinedOrSeparate, attributes: [.frontend, .doesNotAffectIncrementalBuild, .argumentIsPath], helpText: "Add directory to library link search path", group: .linkerOption)
  public static let l: Option = Option("-l", .joinedOrSeparate, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Specifies a library which should be linked against", group: .linkerOption)
  public static let mergeModules: Option = Option("-merge-modules", .flag, attributes: [.frontend, .noDriver], helpText: "Merge the input modules without otherwise processing them", group: .modes)
  public static let migrateKeepObjcVisibility: Option = Option("-migrate-keep-objc-visibility", .flag, attributes: [.frontend, .noInteractive], helpText: "When migrating, add '@objc' to declarations that would've been implicitly visible in Swift 3")
  public static let migratorUpdateSdk: Option = Option("-migrator-update-sdk", .flag, attributes: [.frontend, .noInteractive], helpText: "Does nothing. Temporary compatibility flag for Xcode.")
  public static let migratorUpdateSwift: Option = Option("-migrator-update-swift", .flag, attributes: [.frontend, .noInteractive], helpText: "Does nothing. Temporary compatibility flag for Xcode.")
  public static let migrator: Option = Option("-migrator", .flag, attributes: [.noDriver], helpText: "Dump Json suitable for generating migration script")
  public static let migrator_: Option = Option("--migrator", .flag, alias: Option.migrator, attributes: [.noDriver], helpText: "Dump Json suitable for generating migration script")
  public static let minRuntimeVersion: Option = Option("-min-runtime-version", .separate, attributes: [.helpHidden, .frontend, .noInteractive], helpText: "Specify the minimum runtime version to build force on non-Darwin systems")
  public static let minimumAccessLevel: Option = Option("-minimum-access-level", .separate, attributes: [.noDriver], metaVar: "<level>", helpText: "Include symbols with this access level or more")
  public static let moduleAbiName: Option = Option("-module-abi-name", .separate, attributes: [.frontend, .moduleInterface], helpText: "ABI name to use for the contents of this module")
  public static let moduleAlias: Option = Option("-module-alias", .separate, attributes: [.frontend, .moduleInterface], metaVar: "<alias_name=real_name>", helpText: "If a source file imports or references module <alias_name>, the <real_name> is used for the contents of the file")
  public static let moduleCachePath: Option = Option("-module-cache-path", .separate, attributes: [.frontend, .doesNotAffectIncrementalBuild, .argumentIsPath], helpText: "Specifies the module cache path")
  public static let moduleCanImportVersion: Option = Option("-module-can-import-version", .multiArg, attributes: [.frontend, .noDriver], metaVar: "<moduleName> <version> <underlyingVersion>", helpText: "Specify canImport module and versions", numArgs: 3)
  public static let moduleCanImport: Option = Option("-module-can-import", .separate, attributes: [.frontend, .noDriver], metaVar: "<moduleName>", helpText: "Specify canImport module name")
  public static let moduleInterfacePreserveTypesAsWritten: Option = Option("-module-interface-preserve-types-as-written", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "When emitting a module interface, preserve types as they were written in the source")
  public static let moduleLinkNameEQ: Option = Option("-module-link-name=", .joined, alias: Option.moduleLinkName, attributes: [.frontend])
  public static let moduleLinkName: Option = Option("-module-link-name", .separate, attributes: [.frontend, .moduleInterface], helpText: "Library to link against when using this module")
  public static let moduleListFile: Option = Option("-module-list-file", .joinedOrSeparate, attributes: [.noDriver, .argumentIsPath], helpText: "File containing a new-line separated list of modules")
  public static let moduleLoadMode: Option = Option("-module-load-mode", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "only-interface|prefer-interface|prefer-serialized|only-serialized", helpText: "Module loading mode")
  public static let moduleNameEQ: Option = Option("-module-name=", .joined, alias: Option.moduleName, attributes: [.frontend])
  public static let moduleName: Option = Option("-module-name", .separate, attributes: [.frontend, .moduleInterface], helpText: "Name of the module to build")
  public static let module: Option = Option("-module", .separate, attributes: [.noDriver], metaVar: "<name>", helpText: "Names of modules")
  public static let module_: Option = Option("--module", .separate, alias: Option.module, attributes: [.noDriver], metaVar: "<name>", helpText: "Names of modules")
  public static let newDriverPath: Option = Option("-new-driver-path", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<path>", helpText: "Path of the new driver to be used")
  public static let noAllocations: Option = Option("-no-allocations", .flag, attributes: [.helpHidden, .frontend], helpText: "Diagnose any code that needs to heap allocate (classes, closures, etc.)")
  public static let noClangIncludeTree: Option = Option("-no-clang-include-tree", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Do not use clang include tree, fallback to use CAS filesystem to build clang modules")
  public static let noClangModuleBreadcrumbs: Option = Option("-no-clang-module-breadcrumbs", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Don't emit DWARF skeleton CUs for imported Clang modules. Use this when building a redistributable static archive.")
  public static let noColorDiagnostics: Option = Option("-no-color-diagnostics", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Do not print diagnostics in color")
  public static let noEmitModuleSeparatelyWMO: Option = Option("-no-emit-module-separately-wmo", .flag, attributes: [.helpHidden], helpText: "Force emitting the swiftmodule in the same job in wmo builds")
  public static let noEmitModuleSeparately: Option = Option("-no-emit-module-separately", .flag, attributes: [.helpHidden], helpText: "Force using merge-module as the incremental build mode")
  public static let noLinkObjcRuntime: Option = Option("-no-link-objc-runtime", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Deprecated")
  public static let noScannerModuleValidation: Option = Option("-no-scanner-module-validation", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Do not validate binary modules in scanner and delegate the validation to swift-frontend")
  public static let noSerializeDebuggingOptions: Option = Option("-no-serialize-debugging-options", .flag, attributes: [.frontend, .noDriver], helpText: "Never serialize options for debugging (default: only for apps)")
  public static let noStaticExecutable: Option = Option("-no-static-executable", .flag, attributes: [.helpHidden], helpText: "Don't statically link the executable")
  public static let noStaticStdlib: Option = Option("-no-static-stdlib", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Don't statically link the Swift standard library")
  public static let noStdlibRpath: Option = Option("-no-stdlib-rpath", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Don't add any rpath entries.")
  public static let noStrictImplicitModuleContext: Option = Option("-no-strict-implicit-module-context", .flag, attributes: [.helpHidden, .frontend], helpText: "Disable the strict forwarding of compilation context to downstream implicit module dependencies")
  public static let noToolchainStdlibRpath: Option = Option("-no-toolchain-stdlib-rpath", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Do not add an rpath entry for the toolchain's standard library (default)")
  public static let noVerifyEmittedModuleInterface: Option = Option("-no-verify-emitted-module-interface", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Don't check that module interfaces emitted during compilation typecheck")
  public static let noWarningsAsErrors: Option = Option("-no-warnings-as-errors", .flag, attributes: [.frontend], helpText: "Don't treat warnings as errors")
  public static let noWholeModuleOptimization: Option = Option("-no-whole-module-optimization", .flag, attributes: [.frontend, .noInteractive], helpText: "Disable optimizing input files together instead of individually")
  public static let driverScanDependenciesNonLib: Option = Option("-nonlib-dependency-scanner", .flag, attributes: [.helpHidden], helpText: "Use calls to `swift-frontend -scan-dependencies` instead of dedicated dependency scanning library")
  public static let nostartfiles: Option = Option("-nostartfiles", .flag, attributes: [.helpHidden, .frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Do not link in the Swift language startup routines")
  public static let nostdimport: Option = Option("-nostdimport", .flag, attributes: [.frontend], helpText: "Don't search the standard library import path for modules")
  public static let numThreads: Option = Option("-num-threads", .separate, attributes: [.frontend, .doesNotAffectIncrementalBuild, .cacheInvariant], metaVar: "<n>", helpText: "Enable multi-threading and specify number of threads")
  public static let omitExtensionBlockSymbols: Option = Option("-omit-extension-block-symbols", .flag, attributes: [.helpHidden, .frontend, .noInteractive, .supplementaryOutput], helpText: "Directly associate members and conformances with the extended nominal when generating symbol graphs instead of emitting 'swift.extension' symbols for extensions to external types")
  public static let Onone: Option = Option("-Onone", .flag, attributes: [.frontend, .moduleInterface], helpText: "Compile without any optimization", group: .O)
  public static let Oplayground: Option = Option("-Oplayground", .flag, attributes: [.helpHidden, .frontend, .moduleInterface], helpText: "Compile with optimizations appropriate for a playground", group: .O)
  public static let Osize: Option = Option("-Osize", .flag, attributes: [.frontend, .moduleInterface], helpText: "Compile with optimizations and target small code size", group: .O)
  public static let Ounchecked: Option = Option("-Ounchecked", .flag, attributes: [.frontend, .moduleInterface], helpText: "Compile with optimizations and remove runtime safety checks", group: .O)
  public static let outputDir: Option = Option("-output-dir", .separate, attributes: [.noDriver, .argumentIsPath], metaVar: "<dir>", helpText: "Output directory")
  public static let outputFileMapEQ: Option = Option("-output-file-map=", .joined, alias: Option.outputFileMap, attributes: [.noInteractive, .argumentIsPath])
  public static let outputFileMap: Option = Option("-output-file-map", .separate, attributes: [.noInteractive, .argumentIsPath], metaVar: "<path>", helpText: "A file which specifies the location of outputs")
  public static let outputFilelist: Option = Option("-output-filelist", .separate, attributes: [.frontend, .noDriver, .cacheInvariant], helpText: "Specify outputs in a file rather than on the command line")
  public static let O: Option = Option("-O", .flag, attributes: [.frontend, .moduleInterface], helpText: "Compile with optimizations", group: .O)
  public static let o: Option = Option("-o", .joinedOrSeparate, attributes: [.frontend, .noInteractive, .autolinkExtract, .moduleWrap, .indent, .argumentIsPath, .cacheInvariant], metaVar: "<file>", helpText: "Write output to <file>")
  public static let packageDescriptionVersion: Option = Option("-package-description-version", .separate, attributes: [.helpHidden, .frontend, .moduleInterface], metaVar: "<vers>", helpText: "The version number to be applied on the input for the PackageDescription availability kind")
  public static let packageName: Option = Option("-package-name", .separate, attributes: [.frontend, .moduleInterface], helpText: "Name of the package the module belongs to")
  public static let parallelScan: Option = Option("-parallel-scan", .flag, attributes: [.frontend, .noDriver], helpText: "Perform dependency scanning in-parallel.")
  public static let parseAsLibrary: Option = Option("-parse-as-library", .flag, attributes: [.frontend, .noInteractive], helpText: "Parse the input file(s) as libraries, not scripts")
  public static let parseSil: Option = Option("-parse-sil", .flag, attributes: [.frontend, .noInteractive], helpText: "Parse the input file as SIL code, not Swift source")
  public static let parseStdlib: Option = Option("-parse-stdlib", .flag, attributes: [.helpHidden, .frontend, .moduleInterface], helpText: "Parse the input file(s) as the Swift standard library")
  public static let parseableOutput: Option = Option("-parseable-output", .flag, attributes: [.noInteractive, .doesNotAffectIncrementalBuild], helpText: "Emit textual output in a parseable format")
  public static let parse: Option = Option("-parse", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Parse input file(s)", group: .modes)
  public static let pcMacro: Option = Option("-pc-macro", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Apply the 'program counter simulation' macro")
  public static let pchDisableValidation: Option = Option("-pch-disable-validation", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable validating the persistent PCH")
  public static let pchOutputDir: Option = Option("-pch-output-dir", .separate, attributes: [.helpHidden, .frontend, .argumentIsPath], helpText: "Directory to persist automatically created precompiled bridging headers")
  public static let placeholderDependencyModuleMap: Option = Option("-placeholder-dependency-module-map-file", .separate, attributes: [.frontend, .noDriver], metaVar: "<path>", helpText: "Specify a JSON file containing information of external Swift module dependencies")
  public static let platformAvailabilityInheritanceMapPath: Option = Option("-platform-availability-inheritance-map-path", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<path>", helpText: "Path of the platform inheritance platform map")
  public static let playgroundHighPerformance: Option = Option("-playground-high-performance", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Omit instrumentation that has a high runtime performance impact")
  public static let playgroundOption: Option = Option("-playground-option", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Provide an option to the playground transform (if enabled)")
  public static let playground: Option = Option("-playground", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Apply the playground semantics and transformation")
  public static let pluginPath: Option = Option("-plugin-path", .separate, attributes: [.frontend, .argumentIsPath], helpText: "Add directory to the plugin search path", group: .pluginSearch)
  public static let prebuiltModuleCachePathEQ: Option = Option("-prebuilt-module-cache-path=", .joined, alias: Option.prebuiltModuleCachePath, attributes: [.frontend, .noDriver, .cacheInvariant])
  public static let prebuiltModuleCachePath: Option = Option("-prebuilt-module-cache-path", .separate, attributes: [.frontend, .noDriver, .cacheInvariant], helpText: "Directory of prebuilt modules for loading module interfaces")
  public static let prefixSerializedDebuggingOptions: Option = Option("-prefix-serialized-debugging-options", .flag, attributes: [.frontend], helpText: "Apply debug prefix mappings to serialized debug info in Swiftmodule files")
  public static let prespecializeGenericMetadata: Option = Option("-prespecialize-generic-metadata", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Statically specialize metadata for generic types at types that are known to be used in source.")
  public static let prettyPrint: Option = Option("-pretty-print", .flag, attributes: [], helpText: "Pretty-print the output JSON")
  public static let previousModuleInstallnameMapFile: Option = Option("-previous-module-installname-map-file", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<path>", helpText: "Path to a Json file indicating module name to installname map for @_originallyDefinedIn")
  public static let primaryFilelist: Option = Option("-primary-filelist", .separate, attributes: [.frontend, .noDriver, .argumentIsFileList], helpText: "Specify primary inputs in a file rather than on the command line")
  public static let primaryFile: Option = Option("-primary-file", .separate, attributes: [.frontend, .noDriver, .argumentIsPath], helpText: "Produce output for this file, not the whole module")
  public static let printAstDecl: Option = Option("-print-ast-decl", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Parse and type-check input file(s) and pretty print declarations from AST(s)", group: .modes)
  public static let printAst: Option = Option("-print-ast", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Parse and type-check input file(s) and pretty print AST(s)", group: .modes)
  public static let printClangStats: Option = Option("-print-clang-stats", .flag, attributes: [.frontend, .noDriver], helpText: "Print Clang importer statistics")
  public static let printEducationalNotes: Option = Option("-print-educational-notes", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Include educational notes in printed diagnostic output, if available")
  public static let printExplicitDependencyGraph: Option = Option("-print-explicit-dependency-graph", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Print the result of module dependency scanning after external module resolution to output")
  public static let printInstCounts: Option = Option("-print-inst-counts", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Before IRGen, count all the various SIL instructions. Must be used in conjunction with -print-stats.")
  public static let printLlvmInlineTree: Option = Option("-print-llvm-inline-tree", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Print the LLVM inline tree.")
  public static let printModule: Option = Option("-print-module", .flag, attributes: [.noDriver], helpText: "Print module names in diagnostics")
  public static let printModule_: Option = Option("--print-module", .flag, alias: Option.printModule, attributes: [.noDriver], helpText: "Print module names in diagnostics")
  public static let printPreprocessedExplicitDependencyGraph: Option = Option("-print-preprocessed-explicit-dependency-graph", .flag, attributes: [.helpHidden], helpText: "Print the result of module dependency scanning to output")
  public static let printStats: Option = Option("-print-stats", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Print various statistics")
  public static let printTargetInfo: Option = Option("-print-target-info", .flag, attributes: [.frontend], metaVar: "<triple>", helpText: "Print target information for the given target <triple>, such as x86_64-apple-macos10.9")
  public static let profileCoverageMapping: Option = Option("-profile-coverage-mapping", .flag, attributes: [.frontend, .noInteractive], helpText: "Generate coverage data for use with profiled execution counts")
  public static let profileGenerate: Option = Option("-profile-generate", .flag, attributes: [.frontend, .noInteractive], helpText: "Generate instrumented code to collect execution counts")
  public static let profileStatsEntities: Option = Option("-profile-stats-entities", .flag, attributes: [.helpHidden, .frontend], helpText: "Profile changes to stats in -stats-output-dir, subdivided by source entity")
  public static let profileStatsEvents: Option = Option("-profile-stats-events", .flag, attributes: [.helpHidden, .frontend], helpText: "Profile changes to stats in -stats-output-dir")
  public static let profileUse: Option = Option("-profile-use=", .commaJoined, attributes: [.frontend, .noInteractive, .argumentIsPath], metaVar: "<profdata>", helpText: "Supply a profdata file to enable profile-guided optimization")
  public static let projectName: Option = Option("-project-name", .separate, attributes: [.frontend], helpText: "Name of the project this module to build belongs to")
  public static let protocolRequirementAllowList: Option = Option("-protocol-requirement-allow-list", .separate, attributes: [.noDriver, .argumentIsPath], metaVar: "<path>", helpText: "File containing a new-line separated list of protocol names")
  public static let protocolRequirementAllowList_: Option = Option("--protocol-requirement-allow-list", .separate, alias: Option.protocolRequirementAllowList, attributes: [.noDriver, .argumentIsPath], metaVar: "<path>", helpText: "File containing a new-line separated list of protocol names")
  public static let publicAutolinkLibrary: Option = Option("-public-autolink-library", .separate, attributes: [.frontend, .noDriver], helpText: "Add public dependent library")
  public static let RaccessNoteEQ: Option = Option("-Raccess-note=", .joined, alias: Option.RaccessNote, attributes: [.frontend, .noDriver])
  public static let RaccessNote: Option = Option("-Raccess-note", .separate, attributes: [.frontend, .noDriver], metaVar: "none|failures|all|all-validate", helpText: "Control access note remarks (default: all)")
  public static let cacheRemarks: Option = Option("-Rcache-compile-job", .flag, attributes: [.frontend, .cacheInvariant], helpText: "Show remarks for compiler caching")
  public static let emitCrossImportRemarks: Option = Option("-Rcross-import", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Emit a remark if a cross-import of a module is triggered.")
  public static let dependencyScanCacheRemarks: Option = Option("-Rdependency-scan-cache", .flag, attributes: [.frontend, .noDriver], helpText: "Emit remarks indicating use of the serialized module dependency scanning cache.")
  public static let readLegacyTypeInfoPathEQ: Option = Option("-read-legacy-type-info-path=", .joined, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Read legacy type layout from the given path instead of default path")
  public static let reflectionMetadataForDebuggerOnly: Option = Option("-reflection-metadata-for-debugger-only", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Emit reflection metadata for debugger only, don't make them available at runtime")
  public static let RemoveRuntimeAsserts: Option = Option("-remove-runtime-asserts", .flag, attributes: [.frontend], helpText: "Remove runtime safety checks.")
  public static let repl: Option = Option("-repl", .flag, attributes: [.helpHidden, .frontend, .noBatch], helpText: "REPL mode (the default if there is no input file)", group: .modes)
  public static let reportErrorsToDebugger: Option = Option("-report-errors-to-debugger", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Deprecated, will be removed in future versions.")
  public static let requireExplicitAvailabilityTarget: Option = Option("-require-explicit-availability-target", .separate, attributes: [.frontend, .noInteractive], metaVar: "<target>", helpText: "Suggest fix-its adding @available(<target>, *) to public declarations without availability")
  public static let requireExplicitAvailabilityEQ: Option = Option("-require-explicit-availability=", .joined, attributes: [.frontend, .noInteractive], metaVar: "<error,warn,ignore>", helpText: "Set diagnostic level to report public declarations without an availability attribute")
  public static let requireExplicitAvailability: Option = Option("-require-explicit-availability", .flag, attributes: [.frontend, .noInteractive], helpText: "Warn on public declarations without an availability attribute")
  public static let requireExplicitSendable: Option = Option("-require-explicit-sendable", .flag, attributes: [.frontend, .noInteractive], helpText: "Require explicit Sendable annotations on public declarations")
  public static let requirementMachineMaxConcreteNesting: Option = Option("-requirement-machine-max-concrete-nesting=", .joined, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Set the maximum concrete type nesting depth before giving up")
  public static let requirementMachineMaxRuleCount: Option = Option("-requirement-machine-max-rule-count=", .joined, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Set the maximum number of rules before giving up")
  public static let requirementMachineMaxRuleLength: Option = Option("-requirement-machine-max-rule-length=", .joined, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Set the maximum rule length before giving up")
  public static let requirementMachineMaxSplitConcreteEquivClassAttempts: Option = Option("-requirement-machine-max-split-concrete-equiv-class-attempts=", .joined, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Set the maximum concrete number of attempts at splitting concrete equivalence classes before giving up. There should never be a reason to change this")
  public static let resolveImports: Option = Option("-resolve-imports", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Parse and resolve imports in input file(s)", group: .modes)
  public static let resourceDir: Option = Option("-resource-dir", .separate, attributes: [.helpHidden, .frontend, .argumentIsPath], metaVar: "</usr/lib/swift>", helpText: "The directory that holds the compiler resource files")
  public static let remarkIndexingSystemModule: Option = Option("-Rindexing-system-module", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Emit a remark when indexing a system module")
  public static let remarkMacroLoading: Option = Option("-Rmacro-loading", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Emit remarks about loaded macro implementations")
  public static let remarkModuleApiImport: Option = Option("-Rmodule-api-import", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Emit remarks about the import bridging in each element composing the API")
  public static let RmoduleInterfaceRebuild: Option = Option("-Rmodule-interface-rebuild", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Emits a remark if an imported module needs to be re-compiled from its module interface")
  public static let remarkLoadingModule: Option = Option("-Rmodule-loading", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Emit remarks about loaded module")
  public static let remarkModuleRecovery: Option = Option("-Rmodule-recovery", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Emit remarks about contextual inconsistencies in loaded modules")
  public static let remarkModuleSerialization: Option = Option("-Rmodule-serialization", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Emit remarks about module serialization")
  public static let RpassMissedEQ: Option = Option("-Rpass-missed=", .joined, attributes: [.frontend], helpText: "Report missed transformations by optimization passes whose name matches the given POSIX regular expression")
  public static let RpassEQ: Option = Option("-Rpass=", .joined, attributes: [.frontend], helpText: "Report performed transformations by optimization passes whose name matches the given POSIX regular expression")
  public static let remarkSkipExplicitInterfaceBuild: Option = Option("-Rskip-explicit-interface-build", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Emit a remark if an explicit module interface invocation has an early exit because the expected output is up-to-date")
  public static let runtimeCompatibilityVersion: Option = Option("-runtime-compatibility-version", .separate, attributes: [.frontend], helpText: "Link compatibility library for Swift runtime version, or 'none'")
  public static let sanitizeAddressUseOdrIndicator: Option = Option("-sanitize-address-use-odr-indicator", .flag, attributes: [.helpHidden, .frontend, .noInteractive], helpText: "When using AddressSanitizer enable ODR indicator globals to avoid false ODR violation reports in partially sanitized programs at the cost of an increase in binary size")
  public static let sanitizeCoverageEQ: Option = Option("-sanitize-coverage=", .commaJoined, attributes: [.frontend, .noInteractive], metaVar: "<type>", helpText: "Specify the type of coverage instrumentation for Sanitizers and additional options separated by commas")
  public static let sanitizeRecoverEQ: Option = Option("-sanitize-recover=", .commaJoined, attributes: [.frontend, .noInteractive], metaVar: "<check>", helpText: "Specify which sanitizer runtime checks (see -sanitize=) will generate instrumentation that allows error recovery. Listed checks should be comma separated. Default behavior is to not allow error recovery.")
  public static let sanitizeStableAbiEQ: Option = Option("-sanitize-stable-abi", .flag, attributes: [.frontend, .noInteractive], helpText: "Link against the Sanitizers stable ABI.")
  public static let sanitizeEQ: Option = Option("-sanitize=", .commaJoined, attributes: [.frontend, .noInteractive], metaVar: "<check>", helpText: "Turn on runtime checks for erroneous behavior.")
  public static let saveOptimizationRecordPasses: Option = Option("-save-optimization-record-passes", .separate, attributes: [.frontend], metaVar: "<regex>", helpText: "Only include passes which match a specified regular expression in the generated optimization record (by default, include all passes)")
  public static let saveOptimizationRecordPath: Option = Option("-save-optimization-record-path", .separate, attributes: [.frontend, .argumentIsPath], helpText: "Specify the file name of any generated optimization record")
  public static let saveOptimizationRecordEQ: Option = Option("-save-optimization-record=", .joined, attributes: [.frontend], metaVar: "<format>", helpText: "Generate an optimization record file in a specific format (default: YAML)")
  public static let saveOptimizationRecord: Option = Option("-save-optimization-record", .flag, attributes: [.frontend], helpText: "Generate a YAML optimization record file")
  public static let saveTemps: Option = Option("-save-temps", .flag, attributes: [.noInteractive, .doesNotAffectIncrementalBuild], helpText: "Save intermediate compilation results")
  public static let scanDependencies: Option = Option("-scan-dependencies", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Scan dependencies of the given Swift sources", group: .modes)
  public static let scannerPrefixMapSdk: Option = Option("-scanner-prefix-map-sdk", .separate, attributes: [], metaVar: "<path>", helpText: "Remap paths within SDK reported by dependency scanner")
  public static let scannerPrefixMapToolchain: Option = Option("-scanner-prefix-map-toolchain", .separate, attributes: [], metaVar: "<path>", helpText: "Remap paths within toolchain directory reported by dependency scanner")
  public static let scannerPrefixMap: Option = Option("-scanner-prefix-map", .separate, attributes: [.frontend], metaVar: "<prefix=replacement>", helpText: "Remap paths reported by dependency scanner")
  public static let sdk: Option = Option("-sdk", .separate, attributes: [.frontend, .argumentIsPath], metaVar: "<sdk>", helpText: "Compile against <sdk>")
  public static let serializeBreakingChangesPath: Option = Option("-serialize-breaking-changes-path", .separate, attributes: [.noInteractive, .argumentIsPath], metaVar: "<path>", helpText: "Serialize breaking changes found by the API digester to <path>")
  public static let serializeDebuggingOptions: Option = Option("-serialize-debugging-options", .flag, attributes: [.frontend, .noDriver], helpText: "Always serialize options for debugging (default: only for apps)")
  public static let serializeDependencyScanCache: Option = Option("-serialize-dependency-scan-cache", .flag, attributes: [.frontend, .noDriver], helpText: "After performing a dependency scan, serialize the scanner's internal state.")
  public static let serializeDiagnosticsPathEQ: Option = Option("-serialize-diagnostics-path=", .joined, alias: Option.serializeDiagnosticsPath, attributes: [.frontend, .noBatch, .argumentIsPath, .supplementaryOutput, .cacheInvariant])
  public static let serializeDiagnosticsPath: Option = Option("-serialize-diagnostics-path", .separate, attributes: [.frontend, .noBatch, .argumentIsPath, .supplementaryOutput, .cacheInvariant], metaVar: "<path>", helpText: "Emit a serialized diagnostics file to <path>")
  public static let serializeDiagnostics: Option = Option("-serialize-diagnostics", .flag, attributes: [.frontend, .noInteractive, .supplementaryOutput, .cacheInvariant], helpText: "Serialize diagnostics in a binary format")
  public static let serializeModuleInterfaceDependencyHashes: Option = Option("-serialize-module-interface-dependency-hashes", .flag, attributes: [.frontend, .noDriver])
  public static let serializeParseableModuleInterfaceDependencyHashes: Option = Option("-serialize-parseable-module-interface-dependency-hashes", .flag, alias: Option.serializeModuleInterfaceDependencyHashes, attributes: [.frontend, .noDriver])
  public static let serializedPathObfuscate: Option = Option("-serialized-path-obfuscate", .separate, attributes: [.frontend, .noDriver], metaVar: "<prefix=replacement>", helpText: "Remap source paths in debug info")
  public static let showDiagnosticsAfterFatal: Option = Option("-show-diagnostics-after-fatal", .flag, attributes: [.frontend, .noDriver], helpText: "Keep emitting subsequent diagnostics after a fatal error")
  public static let debugOnSil: Option = Option("-sil-based-debuginfo", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Write the SIL into a file and generate debug-info to debug on SIL  level.")
  public static let silDebugSerialization: Option = Option("-sil-debug-serialization", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Do not eliminate functions in Mandatory Inlining/SILCombine dead functions. (for debugging only)")
  public static let silInlineCallerBenefitReductionFactor: Option = Option("-sil-inline-caller-benefit-reduction-factor", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<2>", helpText: "Controls the aggressiveness of performance inlining in -Osize mode by reducing the base benefits of a caller (lower value permits more inlining!)")
  public static let silInlineThreshold: Option = Option("-sil-inline-threshold", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<50>", helpText: "Controls the aggressiveness of performance inlining")
  public static let silStopOptznsBeforeLoweringOwnership: Option = Option("-sil-stop-optzns-before-lowering-ownership", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Stop optimizing at SIL time before we lower ownership from SIL. Intended only for SIL ossa tests")
  public static let silUnrollThreshold: Option = Option("-sil-unroll-threshold", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<250>", helpText: "Controls the aggressiveness of loop unrolling")
  public static let silVerifyAll: Option = Option("-sil-verify-all", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Verify SIL after each transform")
  public static let silVerifyNone: Option = Option("-sil-verify-none", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Completely disable SIL verification")
  public static let skipImportInPublicInterface: Option = Option("-skip-import-in-public-interface", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Skip the import statement corresponding to a module name when printing the public interface.")
  public static let skipInheritedDocs: Option = Option("-skip-inherited-docs", .flag, attributes: [.helpHidden, .frontend, .noInteractive, .supplementaryOutput], helpText: "Skip emitting doc comments for members inherited through classes or default implementations")
  public static let skipProtocolImplementations: Option = Option("-skip-protocol-implementations", .flag, attributes: [.helpHidden, .frontend, .noInteractive, .supplementaryOutput], helpText: "Skip emitting symbols that are implementations of protocol requirements or inherited from protocol extensions")
  public static let skipSynthesizedMembers: Option = Option("-skip-synthesized-members", .flag, attributes: [.noDriver], helpText: "Skip members inherited through classes or default implementations")
  public static let solverDisableShrink: Option = Option("-solver-disable-shrink", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Disable the shrink phase of expression type checking")
  public static let solverExpressionTimeThresholdEQ: Option = Option("-solver-expression-time-threshold=", .joined, attributes: [.helpHidden, .frontend, .noDriver])
  public static let solverMemoryThreshold: Option = Option("-solver-memory-threshold", .separate, attributes: [.helpHidden, .frontend, .doesNotAffectIncrementalBuild], helpText: "Set the upper bound for memory consumption, in bytes, by the constraint solver")
  public static let solverShrinkUnsolvedThreshold: Option = Option("-solver-shrink-unsolved-threshold", .separate, attributes: [.helpHidden, .frontend, .doesNotAffectIncrementalBuild], helpText: "Set The upper bound to number of sub-expressions unsolved before termination of the shrink phrase")
  public static let stackPromotionLimit: Option = Option("-stack-promotion-limit", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Limit the size of stack promoted objects to the provided number of bytes.")
  public static let staticExecutable: Option = Option("-static-executable", .flag, helpText: "Statically link the executable")
  public static let staticStdlib: Option = Option("-static-stdlib", .flag, attributes: [.doesNotAffectIncrementalBuild], helpText: "Statically link the Swift standard library")
  public static let `static`: Option = Option("-static", .flag, attributes: [.frontend, .noInteractive, .moduleInterface], helpText: "Make this module statically linkable and make the output of -emit-library a static library.")
  public static let statsOutputDir: Option = Option("-stats-output-dir", .separate, attributes: [.helpHidden, .frontend, .argumentIsPath], helpText: "Directory to write unified compilation-statistics files to")
  public static let strictConcurrency: Option = Option("-strict-concurrency=", .joined, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Specify the how strict concurrency checking will be. The value may be 'minimal' (most 'Sendable' checking is disabled), 'targeted' ('Sendable' checking is enabled in code that uses the concurrency model, or 'complete' ('Sendable' and other checking is enabled for all code in the module)")
  public static let strictImplicitModuleContext: Option = Option("-strict-implicit-module-context", .flag, attributes: [.helpHidden, .frontend], helpText: "Enable the strict forwarding of compilation context to downstream implicit module dependencies")
  public static let supplementaryOutputFileMap: Option = Option("-supplementary-output-file-map", .separate, attributes: [.frontend, .noDriver, .cacheInvariant], helpText: "Specify supplementary outputs in a file rather than on the command line")
  public static let suppressRemarks: Option = Option("-suppress-remarks", .flag, attributes: [.frontend], helpText: "Suppress all remarks")
  public static let suppressStaticExclusivitySwap: Option = Option("-suppress-static-exclusivity-swap", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Suppress static violations of exclusive access with swap()")
  public static let suppressWarnings: Option = Option("-suppress-warnings", .flag, attributes: [.frontend], helpText: "Suppress all warnings")
  public static let swiftAsyncFramePointerEQ: Option = Option("-swift-async-frame-pointer=", .joined, attributes: [.helpHidden, .frontend, .noDriver], helpText: "One of 'auto', 'always' or 'never'")
  public static let swiftModuleCrossImport: Option = Option("-swift-module-cross-import", .multiArg, attributes: [.frontend, .noDriver], metaVar: "<moduleName> <crossImport.swiftoverlay>", helpText: "Specify the cross import module", numArgs: 2)
  public static let swiftModuleFile: Option = Option("-swift-module-file=", .joined, attributes: [.frontend, .noDriver], metaVar: "<name>=<path>", helpText: "Specify Swift module input explicitly built from textual interface")
  public static let swiftOnly: Option = Option("-swift-only", .flag, attributes: [.noDriver], helpText: "Only include APIs defined from Swift source")
  public static let swiftOnly_: Option = Option("--swift-only", .flag, alias: Option.swiftOnly, attributes: [.noDriver], helpText: "Only include APIs defined from Swift source")
  public static let swiftVersion: Option = Option("-swift-version", .separate, attributes: [.frontend, .moduleInterface], metaVar: "<vers>", helpText: "Interpret input according to a specific Swift language version number")
  public static let switchCheckingInvocationThresholdEQ: Option = Option("-switch-checking-invocation-threshold=", .joined, attributes: [.helpHidden, .frontend, .noDriver])
  public static let symbolGraphMinimumAccessLevel: Option = Option("-symbol-graph-minimum-access-level", .separate, attributes: [.helpHidden, .frontend, .noInteractive, .supplementaryOutput], metaVar: "<level>", helpText: "Include symbols with this access level or more when emitting a symbol graph")
  public static let sysroot: Option = Option("-sysroot", .separate, attributes: [.frontend, .argumentIsPath], metaVar: "<sysroot>", helpText: "Native Platform sysroot")
  public static let S: Option = Option("-S", .flag, alias: Option.emitAssembly, attributes: [.frontend, .noInteractive], group: .modes)
  public static let tabWidth: Option = Option("-tab-width", .separate, attributes: [.noInteractive, .noBatch, .indent], metaVar: "<n>", helpText: "Width of tab character.", group: .codeFormatting)
  public static let targetCpu: Option = Option("-target-cpu", .separate, attributes: [.frontend, .moduleInterface], helpText: "Generate code for a particular CPU variant")
  public static let minInliningTargetVersion: Option = Option("-target-min-inlining-version", .separate, attributes: [.frontend, .moduleInterface], helpText: "Require inlinable code with no '@available' attribute to back-deploy to this version of the '-target' OS")
  public static let targetSdkName: Option = Option("-target-sdk-name", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Canonical name of the target SDK used for compilation")
  public static let targetSdkVersion: Option = Option("-target-sdk-version", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "The version of target SDK used for compilation")
  public static let targetVariantSdkVersion: Option = Option("-target-variant-sdk-version", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "The version of target variant SDK used for compilation")
  public static let targetVariant: Option = Option("-target-variant", .separate, attributes: [.frontend], helpText: "Generate 'zippered' code for macCatalyst that can run on the specified variant target triple in addition to the main -target triple")
  public static let targetLegacySpelling: Option = Option("--target=", .joined, alias: Option.target, attributes: [.frontend])
  public static let target: Option = Option("-target", .separate, attributes: [.frontend, .moduleWrap, .moduleInterface], metaVar: "<triple>", helpText: "Generate code for the given target <triple>, such as x86_64-apple-macos10.9")
  public static let tbdCompatibilityVersionEQ: Option = Option("-tbd-compatibility-version=", .joined, alias: Option.tbdCompatibilityVersion, attributes: [.frontend, .noDriver])
  public static let tbdCompatibilityVersion: Option = Option("-tbd-compatibility-version", .separate, attributes: [.frontend, .noDriver], metaVar: "<version>", helpText: "The compatibility_version to use in an emitted TBD file")
  public static let tbdCurrentVersionEQ: Option = Option("-tbd-current-version=", .joined, alias: Option.tbdCurrentVersion, attributes: [.frontend, .noDriver])
  public static let tbdCurrentVersion: Option = Option("-tbd-current-version", .separate, attributes: [.frontend, .noDriver], metaVar: "<version>", helpText: "The current_version to use in an emitted TBD file")
  public static let tbdInstallNameEQ: Option = Option("-tbd-install_name=", .joined, alias: Option.tbdInstallName, attributes: [.frontend, .noDriver])
  public static let tbdInstallName: Option = Option("-tbd-install_name", .separate, attributes: [.frontend, .noDriver], metaVar: "<path>", helpText: "The install_name to use in an emitted TBD file")
  public static let tbdIsInstallapi: Option = Option("-tbd-is-installapi", .flag, attributes: [.frontend, .noDriver], helpText: "If the TBD file should indicate it's being generated during InstallAPI")
  public static let debugTestDependencyScanCacheSerialization: Option = Option("-test-dependency-scan-cache-serialization", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "After performing a dependency scan, serialize and then deserialize the scanner's internal state.")
  public static let testableImportModule: Option = Option("-testable-import-module", .separate, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Implicitly import the specified module with @testable")
  public static let throwsAsTraps: Option = Option("-throws-as-traps", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Turn all throw sites into immediate traps")
  public static let toolchainStdlibRpath: Option = Option("-toolchain-stdlib-rpath", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Add an rpath entry for the toolchain's standard library, rather than the OS's")
  public static let toolsDirectory: Option = Option("-tools-directory", .separate, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild, .argumentIsPath], metaVar: "<directory>", helpText: "Look for external executables (ld, clang, binutils) in <directory>")
  public static let traceStatsEvents: Option = Option("-trace-stats-events", .flag, attributes: [.helpHidden, .frontend], helpText: "Trace changes to stats in -stats-output-dir")
  public static let trackSystemDependencies: Option = Option("-track-system-dependencies", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Track system dependencies while emitting Make-style dependencies")
  public static let trapFunction: Option = Option("-trap-function", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<name>", helpText: "Lower traps to calls to this function instead of trap instructions")
  public static let triple: Option = Option("-triple", .separate, alias: Option.target, attributes: [.frontend, .noDriver])
  public static let typeInfoDumpFilterEQ: Option = Option("-type-info-dump-filter=", .joined, attributes: [.helpHidden, .frontend, .noDriver], helpText: "One of 'all', 'resilient' or 'fragile'")
  public static let typecheckModuleFromInterface: Option = Option("-typecheck-module-from-interface", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Treat the (single) input as a swiftinterface and typecheck it", group: .modes)
  public static let typecheck: Option = Option("-typecheck", .flag, attributes: [.frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Parse and type-check input file(s)", group: .modes)
  public static let typoCorrectionLimit: Option = Option("-typo-correction-limit", .separate, attributes: [.helpHidden, .frontend], metaVar: "<n>", helpText: "Limit the number of times the compiler will attempt typo correction to <n>")
  public static let unavailableDeclOptimizationEQ: Option = Option("-unavailable-decl-optimization=", .joined, attributes: [.frontend, .noInteractive], metaVar: "<complete,none>", helpText: "Specify the optimization mode for unavailable declarations. The value may be 'none' (no optimization) or 'complete' (code is not generated at all unavailable declarations)")
  public static let updateCode: Option = Option("-update-code", .flag, attributes: [.helpHidden, .frontend, .noInteractive, .doesNotAffectIncrementalBuild], helpText: "Update Swift code")
  public static let useClangFunctionTypes: Option = Option("-use-clang-function-types", .flag, attributes: [.frontend, .noDriver], helpText: "Use stored Clang function types for computing canonical types.")
  public static let useFrontendParseableOutput: Option = Option("-use-frontend-parseable-output", .flag, attributes: [.helpHidden, .cacheInvariant], helpText: "Emit parseable-output from swift-frontend jobs instead of from the driver")
  public static let useInterfaceForModule: Option = Option("-use-interface-for-module", .separate, attributes: [.noDriver], metaVar: "<name>", helpText: "Prefer loading these modules via interface")
  public static let useInterfaceForModule_: Option = Option("--use-interface-for-module", .separate, alias: Option.useInterfaceForModule, attributes: [.noDriver], metaVar: "<name>", helpText: "Prefer loading these modules via interface")
  public static let useJit: Option = Option("-use-jit", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Register Objective-C classes as if the JIT were in use")
  public static let useLd: Option = Option("-use-ld=", .joined, attributes: [.doesNotAffectIncrementalBuild], helpText: "Specifies the flavor of the linker to be used")
  public static let useMalloc: Option = Option("-use-malloc", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Allocate internal data structures using malloc (for memory debugging)")
  public static let useStaticResourceDir: Option = Option("-use-static-resource-dir", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Use resources in the static resource directory")
  public static let useTabs: Option = Option("-use-tabs", .flag, attributes: [.noInteractive, .noBatch, .indent], helpText: "Use tabs for indentation.", group: .codeFormatting)
  public static let userModuleVersion: Option = Option("-user-module-version", .separate, attributes: [.frontend, .moduleInterface], metaVar: "<vers>", helpText: "Module version specified from Swift module authors")
  public static let validateClangModulesOnce: Option = Option("-validate-clang-modules-once", .flag, attributes: [.frontend], helpText: "Don't verify input files for Clang modules if the module has been successfully validated or loaded during this build session")
  public static let validateTbdAgainstIrEQ: Option = Option("-validate-tbd-against-ir=", .joined, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<level>", helpText: "Compare the symbols in the IR against the TBD file that would be generated.")
  public static let valueRecursionThreshold: Option = Option("-value-recursion-threshold", .separate, attributes: [.helpHidden, .frontend, .doesNotAffectIncrementalBuild], helpText: "Set the maximum depth for direct recursion in value types")
  public static let verifyAdditionalFile: Option = Option("-verify-additional-file", .separate, attributes: [.frontend, .noDriver], helpText: "Verify diagnostics in this file in addition to source files")
  public static let verifyAdditionalPrefix: Option = Option("-verify-additional-prefix", .separate, attributes: [.frontend, .noDriver], helpText: "Check for diagnostics with the prefix expected-<PREFIX> as well as expected-")
  public static let verifyAllSubstitutionMaps: Option = Option("-verify-all-substitution-maps", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Verify all SubstitutionMaps on construction")
  public static let verifyApplyFixes: Option = Option("-verify-apply-fixes", .flag, attributes: [.frontend, .noDriver], helpText: "Like -verify, but updates the original source file")
  public static let verifyDebugInfo: Option = Option("-verify-debug-info", .flag, attributes: [.noInteractive, .doesNotAffectIncrementalBuild], helpText: "Verify the binary representation of debug output.")
  public static let verifyEmittedModuleInterface: Option = Option("-verify-emitted-module-interface", .flag, attributes: [.noInteractive, .doesNotAffectIncrementalBuild], helpText: "Check that module interfaces emitted during compilation typecheck")
  public static let verifyGenericSignatures: Option = Option("-verify-generic-signatures", .separate, attributes: [.frontend, .noDriver], metaVar: "<module-name>", helpText: "Verify the generic signatures in the given module")
  public static let verifyIgnoreUnknown: Option = Option("-verify-ignore-unknown", .flag, attributes: [.frontend, .noDriver], helpText: "Allow diagnostics for '<unknown>' location in verify mode")
  public static let verifyIncrementalDependencies: Option = Option("-verify-incremental-dependencies", .flag, attributes: [.helpHidden, .frontend], helpText: "Enable the dependency verifier for each frontend job")
  public static let verifyTypeLayout: Option = Option("-verify-type-layout", .joinedOrSeparate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<type>", helpText: "Verify compile-time and runtime type layout information for type")
  public static let verify: Option = Option("-verify", .flag, attributes: [.frontend, .noDriver], helpText: "Verify diagnostics against expected-{error|warning|note} annotations")
  public static let version: Option = Option("-version", .flag, attributes: [.frontend], helpText: "Print version information and exit")
  public static let version_: Option = Option("--version", .flag, alias: Option.version, attributes: [.frontend], helpText: "Print version information and exit")
  public static let vfsoverlayEQ: Option = Option("-vfsoverlay=", .joined, alias: Option.vfsoverlay)
  public static let vfsoverlay: Option = Option("-vfsoverlay", .joinedOrSeparate, attributes: [.frontend, .argumentIsPath], helpText: "Add directory to VFS overlay file")
  public static let visualcToolsRoot: Option = Option("-visualc-tools-root", .separate, attributes: [.frontend, .argumentIsPath], metaVar: "<root>", helpText: "VisualC++ Tools Root")
  public static let visualcToolsVersion: Option = Option("-visualc-tools-version", .separate, attributes: [.frontend], metaVar: "<version>", helpText: "VisualC++ ToolSet Version")
  public static let v: Option = Option("-v", .flag, attributes: [.doesNotAffectIncrementalBuild], helpText: "Show commands to run and use verbose output")
  public static let warnConcurrency: Option = Option("-warn-concurrency", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Warn about code that is unsafe according to the Swift Concurrency model and will become ill-formed in a future language version")
  public static let warnImplicitOverrides: Option = Option("-warn-implicit-overrides", .flag, attributes: [.frontend, .doesNotAffectIncrementalBuild], helpText: "Warn about implicit overrides of protocol members")
  public static let warnLongExpressionTypeCheckingEQ: Option = Option("-warn-long-expression-type-checking=", .joined, alias: Option.warnLongExpressionTypeChecking, attributes: [.helpHidden, .frontend, .noDriver])
  public static let warnLongExpressionTypeChecking: Option = Option("-warn-long-expression-type-checking", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<n>", helpText: "Warns when type-checking a function takes longer than <n> ms")
  public static let warnLongFunctionBodiesEQ: Option = Option("-warn-long-function-bodies=", .joined, alias: Option.warnLongFunctionBodies, attributes: [.helpHidden, .frontend, .noDriver])
  public static let warnLongFunctionBodies: Option = Option("-warn-long-function-bodies", .separate, attributes: [.helpHidden, .frontend, .noDriver], metaVar: "<n>", helpText: "Warns when type-checking a function takes longer than <n> ms")
  public static let warnOnEditorPlaceholder: Option = Option("-warn-on-editor-placeholder", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Downgrade the editor placeholder error to a warning")
  public static let warnOnPotentiallyUnavailableEnumCase: Option = Option("-warn-on-potentially-unavailable-enum-case", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Deprecated, will be removed in future versions")
  public static let warnSwift3ObjcInferenceComplete: Option = Option("-warn-swift3-objc-inference-complete", .flag, attributes: [.helpHidden, .frontend, .doesNotAffectIncrementalBuild], helpText: "Deprecated, has no effect")
  public static let warnSwift3ObjcInferenceMinimal: Option = Option("-warn-swift3-objc-inference-minimal", .flag, attributes: [.helpHidden, .frontend, .doesNotAffectIncrementalBuild], helpText: "Deprecated, has no effect")
  public static let warnSwift3ObjcInference: Option = Option("-warn-swift3-objc-inference", .flag, alias: Option.warnSwift3ObjcInferenceComplete, attributes: [.helpHidden, .frontend, .doesNotAffectIncrementalBuild])
  public static let warningsAsErrors: Option = Option("-warnings-as-errors", .flag, attributes: [.frontend], helpText: "Treat warnings as errors")
  public static let weakLinkAtTarget: Option = Option("-weak-link-at-target", .flag, attributes: [.helpHidden, .frontend, .noDriver], helpText: "Weakly link symbols for declarations that were introduced at the deployment target. Symbols introduced before the deployment target are still strongly linked.")
  public static let wholeModuleOptimization: Option = Option("-whole-module-optimization", .flag, attributes: [.frontend, .noInteractive], helpText: "Optimize input files together instead of individually")
  public static let windowsSdkRoot: Option = Option("-windows-sdk-root", .separate, attributes: [.frontend, .argumentIsPath], metaVar: "<root>", helpText: "Windows SDK Root")
  public static let windowsSdkVersion: Option = Option("-windows-sdk-version", .separate, attributes: [.frontend], metaVar: "<version>", helpText: "Windows SDK Version")
  public static let wmo: Option = Option("-wmo", .flag, alias: Option.wholeModuleOptimization, attributes: [.helpHidden, .frontend, .noInteractive])
  public static let workingDirectoryEQ: Option = Option("-working-directory=", .joined, alias: Option.workingDirectory)
  public static let workingDirectory: Option = Option("-working-directory", .separate, metaVar: "<path>", helpText: "Resolve file paths relative to the specified directory")
  public static let Xcc: Option = Option("-Xcc", .separate, attributes: [.frontend], metaVar: "<arg>", helpText: "Pass <arg> to the C/C++/Objective-C compiler")
  public static let XclangLinker: Option = Option("-Xclang-linker", .separate, attributes: [.helpHidden], metaVar: "<arg>", helpText: "Pass <arg> to Clang when it is use for linking.")
  public static let Xfrontend: Option = Option("-Xfrontend", .separate, attributes: [.helpHidden], metaVar: "<arg>", helpText: "Pass <arg> to the Swift frontend")
  public static let Xlinker: Option = Option("-Xlinker", .separate, attributes: [.doesNotAffectIncrementalBuild], helpText: "Specifies an option which should be passed to the linker")
  public static let Xllvm: Option = Option("-Xllvm", .separate, attributes: [.helpHidden, .frontend], metaVar: "<arg>", helpText: "Pass <arg> to LLVM.")
  public static let DASHDASH: Option = Option("--", .remaining, attributes: [.frontend, .doesNotAffectIncrementalBuild])
}

extension Option {
  public static var allOptions: [Option] {
    return [
      Option.INPUT,
      Option.HASHHASHHASH,
      Option.abi,
      Option.abi_,
      Option.abortOnModuleFail,
      Option.abortOnModuleFail_,
      Option.accessNotesPathEQ,
      Option.accessNotesPath,
      Option.aliasModuleNamesInModuleInterface,
      Option.allowableClient,
      Option.alwaysCompileOutputFiles,
      Option.analyzeRequirementMachine,
      Option.apiDiffDataDir,
      Option.apiDiffDataFile,
      Option.enableAppExtensionLibrary,
      Option.enableAppExtension,
      Option.AssertConfig,
      Option.AssumeSingleThreaded,
      Option.autolinkForceLoad,
      Option.autolinkLibrary,
      Option.avoidEmitModuleSourceInfo,
      Option.avoidLocation,
      Option.avoidLocation_,
      Option.avoidToolArgs,
      Option.avoidToolArgs_,
      Option.backupModuleInterfacePathEQ,
      Option.backupModuleInterfacePath,
      Option.badFileDescriptorRetryCount,
      Option.baselineDir,
      Option.baselinePath,
      Option.batchScanInputFile,
      Option.BFEQ,
      Option.BF,
      Option.BIEQ,
      Option.BI,
      Option.blockListFile,
      Option.breakageAllowlistPath,
      Option.bridgingHeaderDirectoryForPrint,
      Option.bridgingHeaderPchKey,
      Option.bsdk,
      Option.buildModuleFromParseableInterface,
      Option.bypassBatchModeChecks,
      Option.bypassResilience,
      Option.cacheCompileJob,
      Option.cacheDisableReplay,
      Option.cacheReplayPrefixMap,
      Option.candidateModuleFile,
      Option.casBackendMode,
      Option.casBackend,
      Option.casEmitCasidFile,
      Option.casFs,
      Option.casPath,
      Option.casPluginOption,
      Option.casPluginPath,
      Option.checkApiAvailabilityOnly,
      Option.checkOnoneCompleteness,
      Option.checkedAsyncObjcBridging,
      Option.clangBuildSessionFile,
      Option.clangHeaderExposeDecls,
      Option.clangHeaderExposeModule,
      Option.clangIncludeTreeRoot,
      Option.clangScannerModuleCachePath,
      Option.clangTarget,
      Option.codeCompleteCallPatternHeuristics,
      Option.codeCompleteInitsInPostfixExpr,
      Option.colorDiagnostics,
      Option.compareToBaselinePath,
      Option.compileModuleFromInterface,
      Option.compilerAssertions,
      Option.compilerStyleDiags,
      Option.compilerStyleDiags_,
      Option.concurrencyModelEQ,
      Option.concurrencyModel,
      Option.conditionalRuntimeRecords,
      Option.constGatherProtocolsFile,
      Option.continueBuildingAfterErrors,
      Option.coveragePrefixMap,
      Option.CrossModuleOptimization,
      Option.crosscheckUnqualifiedLookup,
      Option.cxxInteropGettersSettersAsProperties,
      Option.cxxInteropUseOpaquePointerForMoveonly,
      Option.cxxInteroperabilityMode,
      Option.c,
      Option.debugAssertAfterParse,
      Option.debugAssertImmediately,
      Option.debugConstraintsAttempt,
      Option.debugConstraintsOnLineEQ,
      Option.debugConstraintsOnLine,
      Option.debugConstraints,
      Option.debugCrashAfterParse,
      Option.debugCrashImmediately,
      Option.debugCycles,
      Option.debugDiagnosticNames,
      Option.debugEmitInvalidSwiftinterfaceSyntax,
      Option.debugForbidTypecheckPrefix,
      Option.debugGenericSignatures,
      Option.debugInfoFormat,
      Option.debugInfoStoreInvocation,
      Option.debugInverseRequirements,
      Option.debugMapping,
      Option.debugMapping_,
      Option.debugPrefixMap,
      Option.debugRequirementMachine,
      Option.debugTimeExpressionTypeChecking,
      Option.debugTimeFunctionBodies,
      Option.debuggerSupport,
      Option.debuggerTestingTransform,
      Option.defineAvailability,
      Option.dependencyScanCachePath,
      Option.deprecatedIntegratedRepl,
      Option.deserializeDiff,
      Option.deserializeDiff_,
      Option.deserializeSdk,
      Option.deserializeSdk_,
      Option.diagnoseSdk,
      Option.diagnoseSdk_,
      Option.diagnosticDocumentationPath,
      Option.diagnosticStyleEQ,
      Option.diagnosticStyle,
      Option.diagnosticsEditorMode,
      Option.digesterBreakageAllowlistPath,
      Option.digesterMode,
      Option.directClangCc1ModuleBuild,
      Option.disableAccessControl,
      Option.disableActorDataRaceChecks,
      Option.disableAliasModuleNamesInModuleInterface,
      Option.disableAllAutolinking,
      Option.disableArcOpts,
      Option.disableAstVerifier,
      Option.disableAutolinkFrameworks,
      Option.disableAutolinkFramework,
      Option.disableAutolinkLibrary,
      Option.disableAutolinkingRuntimeCompatibilityConcurrency,
      Option.disableAutolinkingRuntimeCompatibilityDynamicReplacements,
      Option.disableAutolinkingRuntimeCompatibility,
      Option.disableAvailabilityChecking,
      Option.disableBatchMode,
      Option.disableBridgingPch,
      Option.disableBuildingInterface,
      Option.disableClangSpi,
      Option.disableClangTarget,
      Option.disableClangimporterSourceImport,
      Option.disableCrossModuleOptimization,
      Option.disableCollocateMetadataFunctions,
      Option.disableColocateTypeDescriptors,
      Option.disableConcreteTypeMetadataMangledNameAccessors,
      Option.disableConstraintSolverPerformanceHacks,
      Option.disableCrossImportOverlaySearch,
      Option.disableCrossImportOverlays,
      Option.cxxInteropDisableRequirementAtImport,
      Option.disableDebuggerShadowCopies,
      Option.disableDeserializationRecovery,
      Option.disableDeserializationSafety,
      Option.disableDiagnosticPasses,
      Option.disableDynamicActorIsolation,
      Option.disableEmitGenericClassRoTList,
      Option.disableExperimentalClangImporterDiagnostics,
      Option.disableExperimentalLifetimeDependenceInference,
      Option.disableExperimentalOpenedExistentialTypes,
      Option.disableExperimentalParserRoundTrip,
      Option.disableExperimentalStringProcessing,
      Option.disableFailOnError,
      Option.disableFailOnError_,
      Option.disableForceLoadSymbols,
      Option.disableFragileResilientProtocolWitnesses,
      Option.disableGenericMetadataPrespecialization,
      Option.disableImplicitBacktracingModuleImport,
      Option.disableImplicitConcurrencyModuleImport,
      Option.disableImplicitCxxModuleImport,
      Option.disableImplicitStringProcessingModuleImport,
      Option.disableImplicitSwiftModules,
      Option.disableImportPtrauthFieldFunctionPointers,
      Option.disableIncrementalImports,
      Option.disableIncrementalLlvmCodegeneration,
      Option.disableInferPublicConcurrentValue,
      Option.disableInterfaceLockfile,
      Option.disableInvalidEphemeralnessAsError,
      Option.disableLargeLoadableTypesReg2mem,
      Option.disableLayoutStringValueWitnessesInstantiation,
      Option.disableLayoutStringValueWitnesses,
      Option.disableLegacyTypeInfo,
      Option.disableLifetimeDependenceDiagnostics,
      Option.disableLlvmOptzns,
      Option.disableLlvmValueNames,
      Option.disableLlvmVerify,
      Option.disableMigratorFixits,
      Option.disableModulesValidateSystemHeaders,
      Option.disableNamedLazyImportAsMemberLoading,
      Option.disableNamedLazyMemberLoading,
      Option.disableNewLlvmPassManager,
      Option.disableNewOperatorLookup,
      Option.disableNonfrozenEnumExhaustivityDiagnostics,
      Option.disableNskeyedarchiverDiagnostics,
      Option.disableObjcAttrRequiresFoundationModule,
      Option.disableObjcInterop,
      Option.disableObjectiveCProtocolSymbolicReferences,
      Option.disableOnlyOneDependencyFile,
      Option.disableOsChecks,
      Option.disableOsChecks_,
      Option.disableOssaCompleteLifetimes,
      Option.disableOssaOpts,
      Option.disableOssaVerifyComplete,
      Option.disablePlaygroundTransform,
      Option.disablePreallocatedInstantiationCaches,
      Option.disablePreviousImplementationCallsInDynamicReplacements,
      Option.disablePrintMissingImportsInModuleInterface,
      Option.disableReadonlyStaticObjects,
      Option.disableReflectionMetadata,
      Option.disableReflectionNames,
      Option.disableStrictConcurrencyRegionBasedIsolation,
      Option.disableRelativeProtocolWitnessTables,
      Option.disableRemoveDeprecatedCheck,
      Option.disableRemoveDeprecatedCheck_,
      Option.disableRequirementMachineConcreteContraction,
      Option.disableRequirementMachineLoopNormalization,
      Option.disableRequirementMachineReuse,
      Option.disableRoundTripDebugTypes,
      Option.disableSandbox,
      Option.disableSendingArgsAndResultsWithRegionIsolation,
      Option.disableSilOpaqueValues,
      Option.disableSilOwnershipVerifier,
      Option.disableSilPartialApply,
      Option.disableSilPerfOptzns,
      Option.disableStackProtector,
      Option.disableStandardSubstitutionsInReflectionMangling,
      Option.disableSubstSilFunctionTypes,
      Option.disableSwiftBridgeAttr,
      Option.disableSwiftSpecificLlvmOptzns,
      Option.disableSwift3ObjcInference,
      Option.disableTargetOsChecking,
      Option.disableTestableAttrRequiresTestableModule,
      Option.disableTransferringArgsAndResultsWithRegionIsolation,
      Option.disableTypeLayouts,
      Option.disableTypoCorrection,
      Option.disableVerifyExclusivity,
      Option.disallowForwardingDriver,
      Option.downgradeTypecheckInterfaceError,
      Option.driverAlwaysRebuildDependents,
      Option.driverBatchCount,
      Option.driverBatchSeed,
      Option.driverBatchSizeLimit,
      Option.driverEmitFineGrainedDependencyDotFileAfterEveryImport,
      Option.driverFilelistThresholdEQ,
      Option.driverFilelistThreshold,
      Option.driverForceResponseFiles,
      Option.driverMode,
      Option.driverPrintActions,
      Option.driverPrintBindings,
      Option.driverPrintDerivedOutputFileMap,
      Option.driverPrintGraphviz,
      Option.driverPrintJobs,
      Option.driverPrintOutputFileMap,
      Option.driverShowIncremental,
      Option.driverShowJobLifecycle,
      Option.driverSkipExecution,
      Option.driverTimeCompilation,
      Option.driverUseFilelists,
      Option.driverUseFrontendPath,
      Option.driverVerifyFineGrainedDependencyGraphAfterEveryImport,
      Option.driverWarnUnusedOptions,
      Option.dumpApiPath,
      Option.dumpAst,
      Option.dumpClangDiagnostics,
      Option.dumpClangLookupTables,
      Option.dumpInterfaceHash,
      Option.dumpJit,
      Option.dumpMacroExpansions,
      Option.dumpMigrationStatesDir,
      Option.dumpParse,
      Option.dumpPcm,
      Option.dumpRequirementMachine,
      Option.dumpScopeMaps,
      Option.dumpSdk,
      Option.dumpSdk_,
      Option.dumpTypeInfo,
      Option.dumpTypeRefinementContexts,
      Option.dumpTypeWitnessSystems,
      Option.dumpUsr,
      Option.dwarfVersion,
      Option.D,
      Option.embedBitcodeMarker,
      Option.embedBitcode,
      Option.embedTbdForModule,
      Option.emitAbiDescriptorPath,
      Option.emitApiDescriptorPath,
      Option.emitApiDescriptor,
      Option.emitAssembly,
      Option.emitAst,
      Option.emitBc,
      Option.emitClangHeaderNonmodularIncludes,
      Option.emitClangHeaderPath,
      Option.emitConstValuesPath,
      Option.emitConstValues,
      Option.emitDependenciesPath,
      Option.emitDependencies,
      Option.emitDigesterBaselinePath,
      Option.emitDigesterBaseline,
      Option.emitEmptyObjectFile,
      Option.emitExecutable,
      Option.emitExtensionBlockSymbols,
      Option.emitFineGrainedDependencySourcefileDotFiles,
      Option.emitFixitsPath,
      Option.emitImportedModules,
      Option.emitIrgen,
      Option.emitIr,
      Option.emitLibrary,
      Option.emitLoadedModuleTracePathEQ,
      Option.emitLoadedModuleTracePath,
      Option.emitLoadedModuleTrace,
      Option.emitMacroExpansionFiles,
      Option.emitMigratedFilePath,
      Option.emitModuleDependenciesPath,
      Option.emitModuleDocPath,
      Option.emitModuleDoc,
      Option.emitModuleInterfacePath,
      Option.emitModuleInterface,
      Option.emitModulePathEQ,
      Option.emitModulePath,
      Option.emitModuleSemanticInfoPath,
      Option.emitModuleSeparatelyWMO,
      Option.emitModuleSerializeDiagnosticsPath,
      Option.emitModuleSourceInfoPath,
      Option.emitModuleSourceInfo,
      Option.emitModuleSummaryPath,
      Option.emitModuleSummary,
      Option.emitModule,
      Option.emitObjcHeaderPath,
      Option.emitObjcHeader,
      Option.emitObject,
      Option.emitPackageModuleInterfacePath,
      Option.emitParseableModuleInterfacePath,
      Option.emitParseableModuleInterface,
      Option.emitParse,
      Option.emitPch,
      Option.emitPcm,
      Option.emitPrivateModuleInterfacePath,
      Option.emitReferenceDependenciesPath,
      Option.emitReferenceDependencies,
      Option.emitRemapFilePath,
      Option.emitSibgen,
      Option.emitSib,
      Option.emitSilgen,
      Option.emitSil,
      Option.emitSortedSil,
      Option.stackPromotionChecks,
      Option.emitSupportedFeatures,
      Option.emitSymbolGraphDir,
      Option.emitSymbolGraph,
      Option.emitTbdPathEQ,
      Option.emitTbdPath,
      Option.emitTbd,
      Option.emitVerboseSil,
      Option.emptyAbiDescriptor,
      Option.emptyBaseline,
      Option.emptyBaseline_,
      Option.enableAccessControl,
      Option.enableActorDataRaceChecks,
      Option.enableAnonymousContextMangledNames,
      Option.enableAstVerifier,
      Option.enableAutolinkingRuntimeCompatibilityBytecodeLayouts,
      Option.enableBareSlashRegex,
      Option.enableBatchMode,
      Option.enableBridgingPch,
      Option.enableBuiltinModule,
      Option.EnbaleCMOEverything,
      Option.enableCollocateMetadataFunctions,
      Option.enableColocateTypeDescriptors,
      Option.copyPropagationStateEQ,
      Option.enableCopyPropagation,
      Option.enableCrossImportOverlays,
      Option.EnbaleDefaultCMO,
      Option.enableDeserializationRecovery,
      Option.enableDeserializationSafety,
      Option.enableDestroyHoisting,
      Option.enableDeterministicCheck,
      Option.enableDynamicReplacementChaining,
      Option.enableEmitGenericClassRoTList,
      Option.enableExperimentalAdditiveArithmeticDerivation,
      Option.enableAsyncDemotion,
      Option.enableExperimentalAsyncTopLevel,
      Option.enableExperimentalConcisePoundFile,
      Option.enableExperimentalConcurrency,
      Option.enableExperimentalCxxInterop,
      Option.enableExperimentalDistributed,
      Option.enableExperimentalEagerClangModuleDiagnostics,
      Option.enableExperimentalFeature,
      Option.enableExperimentalFlowSensitiveConcurrentCaptures,
      Option.enableExperimentalForwardModeDifferentiation,
      Option.enableExperimentalLifetimeDependenceInference,
      Option.enableExperimentalMoveOnly,
      Option.enableExperimentalNamedOpaqueTypes,
      Option.enableExperimentalOpaqueTypeErasure,
      Option.enableExperimentalOpenedExistentialTypes,
      Option.enableExperimentalPairwiseBuildBlock,
      Option.enableExperimentalStaticAssert,
      Option.enableExperimentalStringProcessing,
      Option.enableExplicitExistentialTypes,
      Option.enableFragileResilientProtocolWitnesses,
      Option.enableImplicitBacktracingModuleImport,
      Option.enableImplicitDynamic,
      Option.enableIncrementalImports,
      Option.enableInferPublicConcurrentValue,
      Option.enableInvalidEphemeralnessAsError,
      Option.enableLargeLoadableTypesReg2mem,
      Option.enableLayoutStringValueWitnessesInstantiation,
      Option.enableLayoutStringValueWitnesses,
      Option.enableLexicalLifetimes,
      Option.enableLexicalLifetimesNoArg,
      Option.enableLibraryEvolution,
      Option.enableLifetimeDependenceDiagnostics,
      Option.enableLlvmValueNames,
      Option.enableLlvmVfe,
      Option.enableLlvmWme,
      Option.enableMoveInoutStackProtector,
      Option.enableNewLlvmPassManager,
      Option.enableNewOperatorLookup,
      Option.enableNonfrozenEnumExhaustivityDiagnostics,
      Option.enableNskeyedarchiverDiagnostics,
      Option.enableObjcAttrRequiresFoundationModule,
      Option.enableObjcInterop,
      Option.enableObjectiveCProtocolSymbolicReferences,
      Option.enableOnlyOneDependencyFile,
      Option.enableOperatorDesignatedTypes,
      Option.enableOssaCompleteLifetimes,
      Option.enableOssaModules,
      Option.enableOssaVerifyComplete,
      Option.enablePackMetadataStackPromotion,
      Option.enablePackMetadataStackPromotionNoArg,
      Option.enablePrivateImports,
      Option.enableRelativeProtocolWitnessTables,
      Option.enableRemoveDeprecatedCheck,
      Option.enableRemoveDeprecatedCheck_,
      Option.enableRequirementMachineOpaqueArchetypes,
      Option.enableResilience,
      Option.enableRoundTripDebugTypes,
      Option.enableSilOpaqueValues,
      Option.enableSingleModuleLlvmEmission,
      Option.enableSourceImport,
      Option.enableSpecDevirt,
      Option.enableStackProtector,
      Option.enableSwift3ObjcInference,
      Option.enableTargetOsChecking,
      Option.enableTestableAttrRequiresTestableModule,
      Option.enableTesting,
      Option.enableThrowWithoutTry,
      Option.enableTypeLayouts,
      Option.enableUpcomingFeature,
      Option.enableVerifyExclusivity,
      Option.enableVolatileModules,
      Option.enforceExclusivityEQ,
      Option.entryPointFunctionName,
      Option.experimentalAllowModuleWithCompilerErrors,
      Option.experimentalAllowNonResilientAccess,
      Option.experimentalAllowedReexportedModules,
      Option.experimentalCForeignReferenceTypes,
      Option.experimentalClangImporterDirectCc1Scan,
      Option.experimentalCxxStdlib,
      Option.emitModuleSeparately,
      Option.driverExperimentalExplicitModuleBuild,
      Option.forceWorkaroundBrokenModules,
      Option.experimentalHermeticSealAtLink,
      Option.experimentalLazyTypecheck,
      Option.experimentalOneWayClosureParams,
      Option.experimentalPackageBypassResilience,
      Option.ExperimentalPackageCMO,
      Option.experimentalPackageInterfaceLoad,
      Option.ExperimentalPerformanceAnnotations,
      Option.platformCCallingConventionEQ,
      Option.platformCCallingConvention,
      Option.experimentalPrintFullConvention,
      Option.experimentalSkipAllFunctionBodies,
      Option.experimentalSkipNonExportableDecls,
      Option.experimentalSkipNonInlinableFunctionBodiesWithoutTypes,
      Option.experimentalSkipNonInlinableFunctionBodies,
      Option.experimentalSpiImports,
      Option.experimentalSpiOnlyImports,
      Option.enableExperimentalSwiftBasedClosureSpecialization,
      Option.explainModuleDependency,
      Option.explicitAutoLinking,
      Option.explicitDependencyGraphFormat,
      Option.explicitInterfaceModuleBuild,
      Option.driverExplicitModuleBuild,
      Option.explicitSwiftModuleMap,
      Option.exportAs,
      Option.externalPassPipelineFilename,
      Option.externalPluginPath,
      Option.e,
      Option.FEQ,
      Option.fileCompilationDir,
      Option.filePrefixMap,
      Option.filelist,
      Option.findUsr,
      Option.findUsr_,
      Option.fixitAll,
      Option.forcePublicLinkage,
      Option.forceSingleFrontendInvocation,
      Option.forceStructTypeLayouts,
      Option.framework,
      Option.frontendParseableOutput,
      Option.Fsystem,
      Option.functionSections,
      Option.F,
      Option.gccToolchain,
      Option.gdwarfTypes,
      Option.generateEmptyBaseline,
      Option.generateEmptyBaseline_,
      Option.generateMigrationScript,
      Option.generateMigrationScript_,
      Option.generateNameCorrection,
      Option.generateNameCorrection_,
      Option.glineTablesOnly,
      Option.gnone,
      Option.groupInfoPath,
      Option.legacyGsil,
      Option.g,
      Option.helpHidden,
      Option.helpHidden_,
      Option.help,
      Option.help_,
      Option.h,
      Option.IEQ,
      Option.iframework,
      Option.ignoreAlwaysInline,
      Option.ignoreModuleSourceInfo,
      Option.ignoreSpiGroups,
      Option.ignoreSpiGroups_,
      Option.ignoredUsrs,
      Option.ignoredUsrs_,
      Option.importBridgingHeader,
      Option.importCfTypes,
      Option.importModule,
      Option.importObjcHeader,
      Option.importPrescan,
      Option.importUnderlyingModule,
      Option.inPlace,
      Option.inProcessPluginServerPath,
      Option.includeSpiSymbols,
      Option.incremental,
      Option.indentSwitchCase,
      Option.indentWidth,
      Option.indexFilePath,
      Option.indexFile,
      Option.indexIgnoreClangModules,
      Option.indexIgnoreStdlib,
      Option.indexIgnoreSystemModules,
      Option.indexIncludeLocals,
      Option.indexStorePath,
      Option.indexSystemModules,
      Option.indexUnitOutputPathFilelist,
      Option.indexUnitOutputPath,
      Option.inputFileKey,
      Option.inputPaths,
      Option.inputPaths_,
      Option.internalizeAtLink,
      Option.interpret,
      Option.I,
      Option.i,
      Option.json,
      Option.json_,
      Option.j,
      Option.LEQ,
      Option.ldPath,
      Option.libc,
      Option.libraryLevelEQ,
      Option.libraryLevel,
      Option.lineRange,
      Option.linkObjcRuntime,
      Option.lldbRepl,
      Option.reuseDependencyScanCache,
      Option.loadPluginExecutable,
      Option.loadPluginLibrary,
      Option.locale,
      Option.localizationPath,
      Option.location,
      Option.location_,
      Option.ltoLibrary,
      Option.lto,
      Option.L,
      Option.l,
      Option.mergeModules,
      Option.migrateKeepObjcVisibility,
      Option.migratorUpdateSdk,
      Option.migratorUpdateSwift,
      Option.migrator,
      Option.migrator_,
      Option.minRuntimeVersion,
      Option.minimumAccessLevel,
      Option.moduleAbiName,
      Option.moduleAlias,
      Option.moduleCachePath,
      Option.moduleCanImportVersion,
      Option.moduleCanImport,
      Option.moduleInterfacePreserveTypesAsWritten,
      Option.moduleLinkNameEQ,
      Option.moduleLinkName,
      Option.moduleListFile,
      Option.moduleLoadMode,
      Option.moduleNameEQ,
      Option.moduleName,
      Option.module,
      Option.module_,
      Option.newDriverPath,
      Option.noAllocations,
      Option.noClangIncludeTree,
      Option.noClangModuleBreadcrumbs,
      Option.noColorDiagnostics,
      Option.noEmitModuleSeparatelyWMO,
      Option.noEmitModuleSeparately,
      Option.noLinkObjcRuntime,
      Option.noScannerModuleValidation,
      Option.noSerializeDebuggingOptions,
      Option.noStaticExecutable,
      Option.noStaticStdlib,
      Option.noStdlibRpath,
      Option.noStrictImplicitModuleContext,
      Option.noToolchainStdlibRpath,
      Option.noVerifyEmittedModuleInterface,
      Option.noWarningsAsErrors,
      Option.noWholeModuleOptimization,
      Option.driverScanDependenciesNonLib,
      Option.nostartfiles,
      Option.nostdimport,
      Option.numThreads,
      Option.omitExtensionBlockSymbols,
      Option.Onone,
      Option.Oplayground,
      Option.Osize,
      Option.Ounchecked,
      Option.outputDir,
      Option.outputFileMapEQ,
      Option.outputFileMap,
      Option.outputFilelist,
      Option.O,
      Option.o,
      Option.packageDescriptionVersion,
      Option.packageName,
      Option.parallelScan,
      Option.parseAsLibrary,
      Option.parseSil,
      Option.parseStdlib,
      Option.parseableOutput,
      Option.parse,
      Option.pcMacro,
      Option.pchDisableValidation,
      Option.pchOutputDir,
      Option.placeholderDependencyModuleMap,
      Option.platformAvailabilityInheritanceMapPath,
      Option.playgroundHighPerformance,
      Option.playgroundOption,
      Option.playground,
      Option.pluginPath,
      Option.prebuiltModuleCachePathEQ,
      Option.prebuiltModuleCachePath,
      Option.prefixSerializedDebuggingOptions,
      Option.prespecializeGenericMetadata,
      Option.prettyPrint,
      Option.previousModuleInstallnameMapFile,
      Option.primaryFilelist,
      Option.primaryFile,
      Option.printAstDecl,
      Option.printAst,
      Option.printClangStats,
      Option.printEducationalNotes,
      Option.printExplicitDependencyGraph,
      Option.printInstCounts,
      Option.printLlvmInlineTree,
      Option.printModule,
      Option.printModule_,
      Option.printPreprocessedExplicitDependencyGraph,
      Option.printStats,
      Option.printTargetInfo,
      Option.profileCoverageMapping,
      Option.profileGenerate,
      Option.profileStatsEntities,
      Option.profileStatsEvents,
      Option.profileUse,
      Option.projectName,
      Option.protocolRequirementAllowList,
      Option.protocolRequirementAllowList_,
      Option.publicAutolinkLibrary,
      Option.RaccessNoteEQ,
      Option.RaccessNote,
      Option.cacheRemarks,
      Option.emitCrossImportRemarks,
      Option.dependencyScanCacheRemarks,
      Option.readLegacyTypeInfoPathEQ,
      Option.reflectionMetadataForDebuggerOnly,
      Option.RemoveRuntimeAsserts,
      Option.repl,
      Option.reportErrorsToDebugger,
      Option.requireExplicitAvailabilityTarget,
      Option.requireExplicitAvailabilityEQ,
      Option.requireExplicitAvailability,
      Option.requireExplicitSendable,
      Option.requirementMachineMaxConcreteNesting,
      Option.requirementMachineMaxRuleCount,
      Option.requirementMachineMaxRuleLength,
      Option.requirementMachineMaxSplitConcreteEquivClassAttempts,
      Option.resolveImports,
      Option.resourceDir,
      Option.remarkIndexingSystemModule,
      Option.remarkMacroLoading,
      Option.remarkModuleApiImport,
      Option.RmoduleInterfaceRebuild,
      Option.remarkLoadingModule,
      Option.remarkModuleRecovery,
      Option.remarkModuleSerialization,
      Option.RpassMissedEQ,
      Option.RpassEQ,
      Option.remarkSkipExplicitInterfaceBuild,
      Option.runtimeCompatibilityVersion,
      Option.sanitizeAddressUseOdrIndicator,
      Option.sanitizeCoverageEQ,
      Option.sanitizeRecoverEQ,
      Option.sanitizeStableAbiEQ,
      Option.sanitizeEQ,
      Option.saveOptimizationRecordPasses,
      Option.saveOptimizationRecordPath,
      Option.saveOptimizationRecordEQ,
      Option.saveOptimizationRecord,
      Option.saveTemps,
      Option.scanDependencies,
      Option.scannerPrefixMapSdk,
      Option.scannerPrefixMapToolchain,
      Option.scannerPrefixMap,
      Option.sdk,
      Option.serializeBreakingChangesPath,
      Option.serializeDebuggingOptions,
      Option.serializeDependencyScanCache,
      Option.serializeDiagnosticsPathEQ,
      Option.serializeDiagnosticsPath,
      Option.serializeDiagnostics,
      Option.serializeModuleInterfaceDependencyHashes,
      Option.serializeParseableModuleInterfaceDependencyHashes,
      Option.serializedPathObfuscate,
      Option.showDiagnosticsAfterFatal,
      Option.debugOnSil,
      Option.silDebugSerialization,
      Option.silInlineCallerBenefitReductionFactor,
      Option.silInlineThreshold,
      Option.silStopOptznsBeforeLoweringOwnership,
      Option.silUnrollThreshold,
      Option.silVerifyAll,
      Option.silVerifyNone,
      Option.skipImportInPublicInterface,
      Option.skipInheritedDocs,
      Option.skipProtocolImplementations,
      Option.skipSynthesizedMembers,
      Option.solverDisableShrink,
      Option.solverExpressionTimeThresholdEQ,
      Option.solverMemoryThreshold,
      Option.solverShrinkUnsolvedThreshold,
      Option.stackPromotionLimit,
      Option.staticExecutable,
      Option.staticStdlib,
      Option.`static`,
      Option.statsOutputDir,
      Option.strictConcurrency,
      Option.strictImplicitModuleContext,
      Option.supplementaryOutputFileMap,
      Option.suppressRemarks,
      Option.suppressStaticExclusivitySwap,
      Option.suppressWarnings,
      Option.swiftAsyncFramePointerEQ,
      Option.swiftModuleCrossImport,
      Option.swiftModuleFile,
      Option.swiftOnly,
      Option.swiftOnly_,
      Option.swiftVersion,
      Option.switchCheckingInvocationThresholdEQ,
      Option.symbolGraphMinimumAccessLevel,
      Option.sysroot,
      Option.S,
      Option.tabWidth,
      Option.targetCpu,
      Option.minInliningTargetVersion,
      Option.targetSdkName,
      Option.targetSdkVersion,
      Option.targetVariantSdkVersion,
      Option.targetVariant,
      Option.targetLegacySpelling,
      Option.target,
      Option.tbdCompatibilityVersionEQ,
      Option.tbdCompatibilityVersion,
      Option.tbdCurrentVersionEQ,
      Option.tbdCurrentVersion,
      Option.tbdInstallNameEQ,
      Option.tbdInstallName,
      Option.tbdIsInstallapi,
      Option.debugTestDependencyScanCacheSerialization,
      Option.testableImportModule,
      Option.throwsAsTraps,
      Option.toolchainStdlibRpath,
      Option.toolsDirectory,
      Option.traceStatsEvents,
      Option.trackSystemDependencies,
      Option.trapFunction,
      Option.triple,
      Option.typeInfoDumpFilterEQ,
      Option.typecheckModuleFromInterface,
      Option.typecheck,
      Option.typoCorrectionLimit,
      Option.unavailableDeclOptimizationEQ,
      Option.updateCode,
      Option.useClangFunctionTypes,
      Option.useFrontendParseableOutput,
      Option.useInterfaceForModule,
      Option.useInterfaceForModule_,
      Option.useJit,
      Option.useLd,
      Option.useMalloc,
      Option.useStaticResourceDir,
      Option.useTabs,
      Option.userModuleVersion,
      Option.validateClangModulesOnce,
      Option.validateTbdAgainstIrEQ,
      Option.valueRecursionThreshold,
      Option.verifyAdditionalFile,
      Option.verifyAdditionalPrefix,
      Option.verifyAllSubstitutionMaps,
      Option.verifyApplyFixes,
      Option.verifyDebugInfo,
      Option.verifyEmittedModuleInterface,
      Option.verifyGenericSignatures,
      Option.verifyIgnoreUnknown,
      Option.verifyIncrementalDependencies,
      Option.verifyTypeLayout,
      Option.verify,
      Option.version,
      Option.version_,
      Option.vfsoverlayEQ,
      Option.vfsoverlay,
      Option.visualcToolsRoot,
      Option.visualcToolsVersion,
      Option.v,
      Option.warnConcurrency,
      Option.warnImplicitOverrides,
      Option.warnLongExpressionTypeCheckingEQ,
      Option.warnLongExpressionTypeChecking,
      Option.warnLongFunctionBodiesEQ,
      Option.warnLongFunctionBodies,
      Option.warnOnEditorPlaceholder,
      Option.warnOnPotentiallyUnavailableEnumCase,
      Option.warnSwift3ObjcInferenceComplete,
      Option.warnSwift3ObjcInferenceMinimal,
      Option.warnSwift3ObjcInference,
      Option.warningsAsErrors,
      Option.weakLinkAtTarget,
      Option.wholeModuleOptimization,
      Option.windowsSdkRoot,
      Option.windowsSdkVersion,
      Option.wmo,
      Option.workingDirectoryEQ,
      Option.workingDirectory,
      Option.Xcc,
      Option.XclangLinker,
      Option.Xfrontend,
      Option.Xlinker,
      Option.Xllvm,
      Option.DASHDASH,
    ]
  }
}

extension Option {
  public enum Group {
    case O
    case codeFormatting
    case debugCrash
    case g
    case `internal`
    case internalDebug
    case linkerOption
    case modes
    case pluginSearch
  }
}

extension Option.Group {
  public var name: String {
    switch self {
      case .O:
        return "<optimization level options>"
      case .codeFormatting:
        return "<code formatting options>"
      case .debugCrash:
        return "<automatic crashing options>"
      case .g:
        return "<debug info options>"
      case .`internal`:
        return "<swift internal options>"
      case .internalDebug:
        return "<swift debug/development internal options>"
      case .linkerOption:
        return "<linker-specific options>"
      case .modes:
        return "<mode options>"
      case .pluginSearch:
        return "<plugin search options>"
    }
  }
}

extension Option.Group {
  public var helpText: String? {
    switch self {
      case .O:
        return nil
      case .codeFormatting:
        return nil
      case .debugCrash:
        return nil
      case .g:
        return nil
      case .`internal`:
        return nil
      case .internalDebug:
        return "DEBUG/DEVELOPMENT OPTIONS"
      case .linkerOption:
        return nil
      case .modes:
        return "MODES"
      case .pluginSearch:
        return nil
    }
  }
}
