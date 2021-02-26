//===------------ System.swift - Swift Driver System Utilities ------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if os(macOS)
import Darwin
#elseif os(Windows)
import WinSDK.core.file
#elseif canImport(Glibc)
import Glibc
#endif

#if os(macOS) || os(Linux) || os(Android)
// Adapted from llvm::sys::commandLineFitsWithinSystemLimits.
func commandLineFitsWithinSystemLimits(path: String, args: [String]) -> Bool {
  let upperBound = sysconf(Int32(_SC_ARG_MAX))
  guard upperBound != -1 else {
    // The system reports no limit.
    return true
  }
  // The lower bound for ARG_MAX on a POSIX system
  let lowerBound = Int(_POSIX_ARG_MAX)
  // This the same baseline used by xargs.
  let baseline = 128 * 1024

  var effectiveArgMax = max(min(baseline, upperBound), lowerBound)
  // Conservatively assume environment variables consume half the space.
  effectiveArgMax /= 2

  var commandLineLength = path.utf8.count + 1
  for arg in args {
    #if os(Linux) || os(Android)
      // Linux limits the length of each individual argument to MAX_ARG_STRLEN.
      // There is no available constant, so it is hardcoded here.
      guard arg.utf8.count < 32 * 4096 else {
        return false
      }
    #endif
    commandLineLength += arg.utf8.count + 1
  }
  return commandLineLength < effectiveArgMax
}
#elseif os(Windows)
// See: https://docs.microsoft.com/en-us/windows/win32/fileio/maximum-file-path-limitation
func commandLineFitsWithinSystemLimits(path: String, args: [String]) -> Bool {
  // Known limit for all CreateProcess APIs
  guard (path.utf8.count + 1) + args.map({ $0.utf8.count + 1 }).reduce(0, +) < 32_767 else {
    return false
  }

  // Path component length limit for Unicode APIs
  var maxComponentLength: UInt32 = 0
  withUnsafeMutablePointer(to: &maxComponentLength) { ptr -> Void in
    GetVolumeInformationA(nil, nil, 0, nil, ptr, nil, nil, 0)
  }
  for component in path.split(separator: #"\"#)
    where component.utf8.count < maxComponentLength {
      return false
  }

  return true
}
#else
func commandLineFitsWithinSystemLimits(path: String, args: [String]) -> Bool {
  #warning("missing implementation for current platform")
  return true
}
#endif
