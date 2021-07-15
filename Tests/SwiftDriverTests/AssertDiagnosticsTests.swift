//===--- AssertDiagnosticsTests.swift - Diagnostic Test Assertion Tests ---===//
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

import XCTest
@_spi(Testing) import SwiftDriver

// Yes, these are meta-tests! `assertDiagnostics(do:)` and friends are
// complicated enough to warrant a few tests of their own. To test that they
// fail when they're supposed to, this test class has access to an
// `assertFails(times:during:)` helper; see `FailableTestCase` below for the
// implementation.

class AssertDiagnosticsTests: FailableTestCase {
  func testAssertNoDiagnostics() {
    assertNoDiagnostics { _ in }

    assertFails {
      assertNoDiagnostics { diags in
        diags.emit(error: "something happened")
      }
    }
    assertFails {
      assertNoDiagnostics { diags in
        diags.emit(warning: "hello")
      }
    }

    // Unexpected warnings/notes/remarks are okay
    assertNoDiagnostics { diags in
      diags.emit(note: "hello")
    }
    assertNoDiagnostics { diags in
      diags.emit(remark: "hello")
    }
  }

  func testAssertDiagnostics() {
    assertDiagnostics { diags, match in
      diags.emit(error: "yankees won again")
      match.expect(.error("won"))
    }
    assertDiagnostics { diags, match in
      match.expect(.error("won"))
      diags.emit(error: "yankees won again")
    }

    assertFails(times: 2) {
      assertDiagnostics { diags, match in
        match.expect(.error("lost"))
        diags.emit(error: "yankees won again")
      }
    }

    assertFails(times: 2) {
      assertDiagnostics { diags, match in
        diags.emit(error: "yankees won again")
        diags.emit(error: "yankees won yet again")
      }
    }

    assertFails(times: 2) {
      assertDiagnostics { diags, match in
        match.expect(.error("won"))
        match.expect(.error("won"))
      }
    }

    // We should get two assertion failures: one for expecting the warning, one
    // for emitting the error.
    assertFails(times: 2) {
      assertDiagnostics { diags, match in
        match.expect(.warning("won"))
        diags.emit(.error("yankees won again"))
      }
    }

    // We should get one assertion failure for the unexpected error. An
    // unexpected note is okay.
    assertFails(times: 1) {
      assertDiagnostics { diags, match in
        diags.emit(error: "yankees won again")
        diags.emit(note: "investigate their star's doctor")
      }
    }

    // ...unless we tighten things up.
    assertFails(times: 2) {
      assertDiagnostics { diags, match in
        diags.emit(error: "yankees won again")
        diags.emit(note: "investigate their star's doctor")
        match.forbidUnexpected(.note)
      }
    }

    // ...or loosen them.
    assertDiagnostics { diags, match in
      diags.emit(error: "yankees won again")
      diags.emit(note: "investigate their star's doctor")
      match.permitUnexpected(.error)
    }
  }

  func testAssertDriverDiagosotics() throws {
    try assertNoDriverDiagnostics(args: "swiftc", "test.swift")

    try assertDriverDiagnostics(args: "swiftc", "test.swift") { driver, verify in
      driver.diagnosticEngine.emit(.error("this mode does not support emitting modules"))
      verify.expect(.error("this mode does not support emitting modules"))
    }

    try assertFails {
      try assertDriverDiagnostics(args: "swiftc", "test.swift") { driver, verify in
        verify.expect(.error("this mode does not support emitting modules"))
      }
    }

    try assertFails {
      try assertDriverDiagnostics(args: "swiftc", "test.swift") { driver, verify in
        driver.diagnosticEngine.emit(.error("this mode does not support emitting modules"))
      }
    }

    try assertFails(times: 2) {
      try assertDriverDiagnostics(args: "swiftc", "test.swift") { driver, verify in
        driver.diagnosticEngine.emit(.error("this mode does not support emitting modules"))
        verify.expect(.error("-static may not be used with -emit-executable"))
      }
    }
  }
}

// MARK: - Failure testing

/// Subclasses are considered to pass if exactly the right number of test assertions
/// fail in each `assertFails(times:during:)` block. Failures are recorded
/// if they fail too often or not often enough.
class FailableTestCase: XCTestCase {
  fileprivate var anticipatedFailures = 0

  func assertFails(
    times: Int = 1,
    _ message: String = "",
    file: String = #file,
    line: Int = #line,
    during body: () throws -> Void
  ) rethrows {
    let outer = anticipatedFailures
    anticipatedFailures = times

    defer {
      if anticipatedFailures > 0 {
        let context = XCTSourceCodeContext(
                            location: XCTSourceCodeLocation(
                                filePath: file, lineNumber: line))
        self.record(XCTIssue(type: .assertionFailure,
                             compactDescription: "\(anticipatedFailures) failure(s) were supposed to occur, but did not: \(message)",
                             detailedDescription: nil,
                             sourceCodeContext: context))
      }
      anticipatedFailures = outer
    }

    try body()
  }

  override func setUp() {
    super.setUp()
    anticipatedFailures = 0
  }

  override func record(_ issue: XCTIssue) {
    guard anticipatedFailures == 0 else {
      anticipatedFailures -= 1
      return
    }

    super.record(issue)
  }
}
