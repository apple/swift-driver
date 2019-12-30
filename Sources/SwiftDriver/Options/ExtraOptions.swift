//===--------------- ExtraOptions.swift - Swift Driver Extra Options ------===//
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
extension Option {
  public static let driverPrintGraphviz: Option = Option("-driver-print-graphviz", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Write the job graph as a graphviz file", group: .internalDebug)

  public static let driverPrebuildModuleDependencies: Option = Option("-driver-prebuild-module-dependencies", .flag, attributes: [.helpHidden], helpText: "Prebuild module dependencies to make them explicit")

  public static var extraOptions: [Option] {
    return [
      Option.driverPrintGraphviz,
      Option.driverPrebuildModuleDependencies
    ]
  }
}
