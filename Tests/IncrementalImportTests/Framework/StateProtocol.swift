//===------- IncrementalImportTestFramework.swift - Swift Testing ---------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import XCTest
import TSCBasic

@_spi(Testing) import SwiftDriver
import SwiftOptions
import TestUtilities


// MARK: - StateProtocol

protocol StateProtocol: TestPartProtocol {
  associatedtype Module: ModuleProtocol
  typealias Source = Module.Source

  var jobs: [CompileJob<Module>] {get}
}

extension StateProtocol {
  var name: String {rawValue}

  /// Performs a mutation of the mutable source file
  private func mutate(_ context: TestContext) {
    for job in jobs {
      job.mutate(context)
    }
  }

  /// All (original) sources involved in this state, recompiled or not
  var allOriginals: [Source] {
    Array( jobs.reduce(into: Set<Source>()) { sources, job in
      sources.formUnion(job.originals)
    })
  }

  func buildFromScratch(_ context: TestContext) {
    mutateAndRebuildAndCheck(
      context,
      expecting: expectingFromScratch,
      stepName: "setup")
  }

  func mutateAndRebuildAndCheck(
    _ context: TestContext,
    expecting: [Source],
    stepName: String
  ) {
    print(stepName)

    mutate(context)
    let compiledSources = build(context)
    XCTAssertEqual(
      compiledSources.map {$0.name} .sorted(),
      expecting      .map {$0.name} .sorted(),
      "Compiled != Expected, \(context), step \(stepName)",
      file: context.testFile, line: context.testLine)
  }

  /// Builds the entire project, returning what was recompiled.
   private func build(_ context: TestContext) -> [Source] {
     jobs.flatMap{ $0.build(context) }
   }
  var expectingFromScratch: [Source] {
    Array(
      jobs.reduce(into: Set()) {
        expectations, job in
        expectations.formUnion(job.fromScratchExpectations)
      }
    )
  }


}
