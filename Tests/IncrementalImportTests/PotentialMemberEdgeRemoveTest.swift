//===-------------- ClassExtensionTest.swift - Swift Testing --------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import XCTest
import TSCBasic
import SwiftOptions
import IncrementalTestFramework

final class PotentialMemberEdgeRemoveTest: XCTestCase {
  func testRemovingPotentialMemberEdgeResetsState() throws {
    // MARK: - Define sources & imported module
    let cSource = Source(named: "C", containing: """
        //# updateConstant /*
        public struct C {
            private let value: String = "C"
            public init() {}
            public func doStuff(parameter: Int = 1) { print(self.value) }
        }
        //# updateConstant */
        //# updateConstant public struct C {
        //# updateConstant     private let value: String = "C"
        //# updateConstant     public init() {}
        //# updateConstant     public func doStuff(parameter: Int = 2) { print(self.value) }
        //# updateConstant }
        """)
    let c = Module(named: "C", containing: [cSource], producing: .library)

    let bSource = Source(named: "B", containing: """
        import \(c.name)

        public struct B {
            private let value: String = "B"
            //# privateLet private let c: C = C()
            public init() {}
            public func doStuff() {
                print(value)
                C().doStuff()
            }
        }
        """)
    let b = Module(named: "B", containing: [bSource], importing: [c], producing: .library)

    let aSource = Source(named: "A", containing: """
        import \(b.name)

        public struct A {
            private let value: String = "A"
            private let b: B
            public init() {
                self.b = B()
                print(B())
            }
            public func doStuff() {
                print(value)
                self.b.doStuff()
            }
        }
        """)
    let a = Module(named: "A", containing: [aSource], importing: [b, c], producing: .library)

    let mainSource = Source(named: "main", containing: """
        import \(a.name)

        struct App {
            static func main() {
                let a = A()
                a.doStuff()
            }
        }

        App.main()
        """)

    let mainModule = Module(
      named: "main", containing: [mainSource], importing: [a, b, c], producing: .executable)

    // MARK: - Define the test

    // Define module ordering & what to compile
    let modules = [c, b, a, mainModule]

    let whenUpdatingConstant = ExpectedCompilations(
      always: [cSource, bSource],
      andWhenDisabled: [aSource, mainSource])

    let whenAddRemovePrivateLet = ExpectedCompilations(
      always: [bSource, aSource, mainSource],
      andWhenDisabled: [])

    let steps = [
      Step(                          building: modules, .expecting(modules.allSourcesToCompile)),
      Step(                          building: modules, .expecting(.none)),
      Step(adding: "updateConstant", building: modules, .expecting(whenUpdatingConstant)),
      Step(                          building: modules, .expecting(whenUpdatingConstant)),
      Step(adding: "privateLet",     building: modules, .expecting(whenAddRemovePrivateLet)),
      Step(                          building: modules, .expecting(whenAddRemovePrivateLet)),
      Step(                          building: modules, .expecting(.none)),
      Step(adding: "updateConstant", building: modules, .expecting(whenUpdatingConstant)),
      Step(                          building: modules, .expecting(whenUpdatingConstant)),
    ]

    // Do the test
    try IncrementalTest.perform(steps)
  }
}
