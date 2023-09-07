//===--------------- Diagnostics.swift - Swift Driver Diagnostics ---------===//
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

import SwiftOptions

import struct TSCBasic.Diagnostic

extension Diagnostic.Message {
  static var error_static_emit_executable_disallowed: Diagnostic.Message {
    .error("-static may not be used with -emit-executable")
  }

  static func error_update_code_not_supported(in mode: CompilerMode) -> Diagnostic.Message {
    .error("using '-update-code' in \(mode) mode is not supported")
  }

  static func error_option_missing_required_argument(option: Option, requiredArg: String) -> Diagnostic.Message {
    .error("option '\(option.spelling)' is missing a required argument (\(requiredArg))")
  }

  static func error_opt_invalid_mapping(option: Option, value: String) -> Diagnostic.Message {
    .error("values for '\(option.spelling)' must be in the format 'original=remapped', but '\(value)' was provided")
  }

  static func error_unsupported_argument(argument: String, option: Option) -> Diagnostic.Message {
    .error("unsupported argument '\(argument)' to option '\(option.spelling)'")
  }

  static func error_option_requires_sanitizer(option: Option) -> Diagnostic.Message {
    .error("option '\(option.spelling)' requires a sanitizer to be enabled. Use -sanitize= to enable a sanitizer")
  }

  static func error_invalid_arg_value(arg: Option, value: String) -> Diagnostic.Message {
    .error("invalid value '\(value)' in '\(arg.spelling)'")
  }

  static func error_invalid_arg_value_with_allowed(arg: Option, value: String, options: [String]) -> Diagnostic.Message {
    .error("invalid value '\(value)' in '\(arg.spelling)', valid options are: \(options.joined(separator: ", "))")
  }

  static func warning_inferring_simulator_target(originalTriple: Triple, inferredTriple: Triple) -> Diagnostic.Message {
    .warning("inferring simulator environment for target '\(originalTriple.triple)'; use '-target \(inferredTriple.triple)' instead")
  }

  static func warning_inprocess_target_info_query_failed(_ error: String) -> Diagnostic.Message {
    .warning("In-process target-info query failed (\(error)). Using fallback mechanism.")
  }

  static func warning_inprocess_supported_features_query_failed(_ error: String) -> Diagnostic.Message {
    .warning("In-process supported-compiler-features query failed (\(error)). Using fallback mechanism.")
  }

  static func error_argument_not_allowed_with(arg: String, other: String) -> Diagnostic.Message {
    .error("argument '\(arg)' is not allowed with '\(other)'")
  }

  static func error_unsupported_opt_for_target(arg: String, target: Triple) -> Diagnostic.Message {
    .error("unsupported option '\(arg)' for target '\(target.triple)'")
  }

  static func error_sanitizer_unavailable_on_target(sanitizer: String, target: Triple) -> Diagnostic.Message {
    .error("\(sanitizer) sanitizer is unavailable on target '\(target.triple)'")
  }

  static var error_mode_cannot_emit_module: Diagnostic.Message {
    .error("this mode does not support emitting modules")
  }

  static func error_cannot_read_swiftdeps(file: VirtualPath, reason: String) -> Diagnostic.Message {
    .error("cannot read swiftdeps: \(reason), file: \(file)")
  }

  static func error_bad_module_name(
    moduleName: String,
    explicitModuleName: Bool,
		validationFailureReason reason: String
  ) -> Diagnostic.Message {
    let suffix: String
    if explicitModuleName {
      suffix = ""
    } else {
      suffix = " Use -module-name flag to specify an alternate name"
    }

    return .error("module name \"\(moduleName)\" is not a valid Swift identifier, because \(reason).\(suffix)")
  }

  static func error_stdlib_module_name(
    moduleName: String,
    explicitModuleName: Bool
  ) -> Diagnostic.Message {
    let suffix: String
    if explicitModuleName {
      suffix = ""
    } else {
      suffix = "; use -module-name flag to specify an alternate name"
    }

    return .error("module name \"\(moduleName)\" is reserved for the standard library\(suffix)")
  }

  static func error_bad_module_alias(_ arg: String,
                                     moduleName: String,
                                     formatted: Bool = true,
                                     isDuplicate: Bool = false) -> Diagnostic.Message {
    if !formatted {
      return .error("invalid format \"\(arg)\"; use the format '-module-alias alias_name=underlying_name'")
    }
    if arg == moduleName {
      return .error("module alias \"\(arg)\" should be different from the module name \"\(moduleName)\"")
    }
    if isDuplicate {
      return .error("the name \"\(arg)\" is already used for a module alias or an underlying name")
    }
    return .error("bad module alias \"\(arg)\"")
  }

  static var error_empty_package_name: Diagnostic.Message {
    return .error("package-name is empty")
  }

  static var error_hermetic_seal_cannot_have_library_evolution: Diagnostic.Message {
    .error("Cannot use -experimental-hermetic-seal-at-link with -enable-library-evolution")
  }

  static var error_hermetic_seal_requires_lto: Diagnostic.Message {
    .error("-experimental-hermetic-seal-at-link requires -lto=llvm-full or -lto=llvm-thin")
  }

  static func warning_no_such_sdk(_ path: String) -> Diagnostic.Message {
    .warning("no such SDK: \(path)")
  }

  static func warning_no_sdksettings_json(_ path: String) -> Diagnostic.Message {
      .warning("Could not read SDKSettings.json for SDK at: \(path)")
  }

  static func warning_fail_parse_sdk_ver(_ version: String, _ path: String) -> Diagnostic.Message {
      .warning("Could not parse SDK version '\(version)' at: \(path)")
  }

  static func error_sdk_too_old(_ path: String) -> Diagnostic.Message {
      .error("Swift does not support the SDK \(path)")
  }

  static func error_unknown_target(_ target: String) -> Diagnostic.Message {
    .error("unknown target '\(target)'")
  }

  static func warning_option_overrides_another(overridingOption: Option, overridenOption: Option) -> Diagnostic.Message {
    .warning("ignoring '\(overridenOption.spelling)' because '\(overridingOption.spelling)' was also specified")
  }

  static func error_expected_one_frontend_job() -> Diagnostic.Message {
    .error("unable to handle compilation, expected exactly one frontend job")
  }

  static func error_expected_frontend_command() -> Diagnostic.Message {
    .error("expected a swift frontend command")
  }
}
