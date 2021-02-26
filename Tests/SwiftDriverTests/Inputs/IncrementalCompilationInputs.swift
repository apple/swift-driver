//===--- IncrementalCompilationInputs.swift - Test Inputs -----------------===//
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

import Foundation

enum Inputs {
#if !os(Windows)
  static var buildRecord: String {
    """
        version: "Apple Swift version 5.1 (swiftlang-1100.0.270.13 clang-1100.0.33.7)"
        options: "abbbfbcaf36b93e58efaadd8271ff142"
        build_time: [1570318779, 32358000]
        inputs:
          "/Volumes/AS/repos/swift-driver/sandbox/sandbox/sandbox/file2.swift": !dirty [1570318778, 0]
          "/Volumes/AS/repos/swift-driver/sandbox/sandbox/sandbox/main.swift": [1570083660, 0]
          "/Volumes/gazorp.swift": !private [0,0]
    """
  }
  static var buildRecordWithoutOptions: String {
    """
        version: "Apple Swift version 5.1 (swiftlang-1100.0.270.13 clang-1100.0.33.7)"
        build_time: [1570318779, 32358000]
        inputs:
          "/Volumes/AS/repos/swift-driver/sandbox/sandbox/sandbox/file2.swift": !dirty [1570318778, 0]
          "/Volumes/AS/repos/swift-driver/sandbox/sandbox/sandbox/main.swift": [1570083660, 0]
          "/Volumes/gazorp.swift": !private [0,0]
    """
  }
  static var fineGrainedSourceFileDependencyGraph: String {
    """
    # Fine-grained v0
    ---
    allNodes:
      - key:
          kind:            sourceFileProvide
          aspect:          interface
          context:         ''
          name:            '/Users/owenvoorhees/Desktop/hello.swiftdeps'
        fingerprint:     85188db3503106210367dbcb7f5d1524
        sequenceNumber:  0
        defsIDependUpon: [ 30, 28, 24, 23, 27, 22, 21 ]
        isProvides:      true
      - key:
          kind:            sourceFileProvide
          aspect:          implementation
          context:         ''
          name:            '/Users/owenvoorhees/Desktop/hello.swiftdeps'
        fingerprint:     85188db3503106210367dbcb7f5d1524
        sequenceNumber:  1
        defsIDependUpon: [ 26, 25, 31, 20, 19, 29, 18 ]
        isProvides:      true
      - key:
          kind:            topLevel
          aspect:          interface
          context:         ''
          name:            Foo
        fingerprint:     8daabb8cdf69d8e8702b4788be12efd6
        sequenceNumber:  2
        defsIDependUpon: [ 0 ]
        isProvides:      true
      - key:
          kind:            topLevel
          aspect:          implementation
          context:         ''
          name:            Foo
        fingerprint:     8daabb8cdf69d8e8702b4788be12efd6
        sequenceNumber:  3
        defsIDependUpon: [  ]
        isProvides:      true
      - key:
          kind:            topLevel
          aspect:          interface
          context:         ''
          name:            a
        sequenceNumber:  4
        defsIDependUpon: [ 0 ]
        isProvides:      true
      - key:
          kind:            topLevel
          aspect:          implementation
          context:         ''
          name:            a
        sequenceNumber:  5
        defsIDependUpon: [  ]
        isProvides:      true
      - key:
          kind:            topLevel
          aspect:          interface
          context:         ''
          name:            y
        sequenceNumber:  6
        defsIDependUpon: [ 0 ]
        isProvides:      true
      - key:
          kind:            topLevel
          aspect:          implementation
          context:         ''
          name:            y
        sequenceNumber:  7
        defsIDependUpon: [  ]
        isProvides:      true
      - key:
          kind:            nominal
          aspect:          interface
          context:         SS
          name:            ''
        sequenceNumber:  8
        defsIDependUpon: [ 0 ]
        isProvides:      true
      - key:
          kind:            nominal
          aspect:          implementation
          context:         SS
          name:            ''
        sequenceNumber:  9
        defsIDependUpon: [  ]
        isProvides:      true
      - key:
          kind:            nominal
          aspect:          interface
          context:         5hello3FooV
          name:            ''
        fingerprint:     8daabb8cdf69d8e8702b4788be12efd6
        sequenceNumber:  10
        defsIDependUpon: [ 0 ]
        isProvides:      true
      - key:
          kind:            nominal
          aspect:          implementation
          context:         5hello3FooV
          name:            ''
        fingerprint:     8daabb8cdf69d8e8702b4788be12efd6
        sequenceNumber:  11
        defsIDependUpon: [  ]
        isProvides:      true
      - key:
          kind:            potentialMember
          aspect:          interface
          context:         SS
          name:            ''
        sequenceNumber:  12
        defsIDependUpon: [ 0 ]
        isProvides:      true
      - key:
          kind:            potentialMember
          aspect:          implementation
          context:         SS
          name:            ''
        sequenceNumber:  13
        defsIDependUpon: [  ]
        isProvides:      true
      - key:
          kind:            potentialMember
          aspect:          interface
          context:         5hello3FooV
          name:            ''
        fingerprint:     8daabb8cdf69d8e8702b4788be12efd6
        sequenceNumber:  14
        defsIDependUpon: [ 0 ]
        isProvides:      true
      - key:
          kind:            potentialMember
          aspect:          implementation
          context:         5hello3FooV
          name:            ''
        fingerprint:     8daabb8cdf69d8e8702b4788be12efd6
        sequenceNumber:  15
        defsIDependUpon: [  ]
        isProvides:      true
      - key:
          kind:            member
          aspect:          interface
          context:         SS
          name:            abc
        sequenceNumber:  16
        defsIDependUpon: [ 0 ]
        isProvides:      true
      - key:
          kind:            member
          aspect:          implementation
          context:         SS
          name:            abc
        sequenceNumber:  17
        defsIDependUpon: [  ]
        isProvides:      true
      - key:
          kind:            topLevel
          aspect:          interface
          context:         ''
          name:            StringLiteralType
        sequenceNumber:  18
        defsIDependUpon: [  ]
        isProvides:      false
      - key:
          kind:            topLevel
          aspect:          interface
          context:         ''
          name:            FloatLiteralType
        sequenceNumber:  19
        defsIDependUpon: [  ]
        isProvides:      false
      - key:
          kind:            topLevel
          aspect:          interface
          context:         ''
          name:            IntegerLiteralType
        sequenceNumber:  20
        defsIDependUpon: [  ]
        isProvides:      false
      - key:
          kind:            topLevel
          aspect:          interface
          context:         ''
          name:            String
        sequenceNumber:  21
        defsIDependUpon: [  ]
        isProvides:      false
      - key:
          kind:            topLevel
          aspect:          interface
          context:         ''
          name:            Int
        sequenceNumber:  22
        defsIDependUpon: [  ]
        isProvides:      false
      - key:
          kind:            externalDepend
          aspect:          interface
          context:         ''
          name:            '/Users/owenvoorhees/Documents/Development/swift-source/build/Ninja-ReleaseAssert/swift-macosx-x86_64/lib/swift/macosx/Swift.swiftmodule/x86_64-apple-macos.swiftmodule'
        sequenceNumber:  23
        defsIDependUpon: [  ]
        isProvides:      false
      - key:
          kind:            externalDepend
          aspect:          interface
          context:         ''
          name:            '/Users/owenvoorhees/Documents/Development/swift-source/build/Ninja-ReleaseAssert/swift-macosx-x86_64/lib/swift/macosx/SwiftOnoneSupport.swiftmodule/x86_64-apple-macos.swiftmodule'
        sequenceNumber:  24
        defsIDependUpon: [  ]
        isProvides:      false
      - key:
          kind:            nominal
          aspect:          interface
          context:         s35_ExpressibleByBuiltinIntegerLiteralP
          name:            ''
        sequenceNumber:  25
        defsIDependUpon: [  ]
        isProvides:      false
      - key:
          kind:            nominal
          aspect:          interface
          context:         s34_ExpressibleByBuiltinStringLiteralP
          name:            ''
        sequenceNumber:  26
        defsIDependUpon: [  ]
        isProvides:      false
      - key:
          kind:            member
          aspect:          interface
          context:         5hello3FooV
          name:            init
        sequenceNumber:  27
        defsIDependUpon: [  ]
        isProvides:      false
      - key:
          kind:            member
          aspect:          interface
          context:         SS
          name:            Int
        sequenceNumber:  28
        defsIDependUpon: [  ]
        isProvides:      false
      - key:
          kind:            member
          aspect:          interface
          context:         s35_ExpressibleByBuiltinIntegerLiteralP
          name:            init
        sequenceNumber:  29
        defsIDependUpon: [  ]
        isProvides:      false
      - key:
          kind:            member
          aspect:          interface
          context:         5hello3FooV
          name:            baz
        sequenceNumber:  30
        defsIDependUpon: [  ]
        isProvides:      false
      - key:
          kind:            member
          aspect:          interface
          context:         s34_ExpressibleByBuiltinStringLiteralP
          name:            init
        sequenceNumber:  31
        defsIDependUpon: [  ]
        isProvides:      false
    ...

    """
  }
#else
  static var buildRecord: String {
    #"""
        version: "Apple Swift version 5.1 (swiftlang-1100.0.270.13 clang-1100.0.33.7)"
        options: "abbbfbcaf36b93e58efaadd8271ff142"
        build_time: [1570318779, 32358000]
        inputs:
          "C:\\repos\\swift-driver\\sandbox\\sandbox\\sandbox\\file2.swift": !dirty [1570318778, 0]
          "C:\\repos\\swift-driver\\sandbox\\sandbox\\sandbox\\main.swift": [1570083660, 0]
          "E:\\gazorp.swift": !private [0,0]
    """#
  }
  static var buildRecordWithoutOptions: String {
    #"""
        version: "Apple Swift version 5.1 (swiftlang-1100.0.270.13 clang-1100.0.33.7)"
        build_time: [1570318779, 32358000]
        inputs:
          "C:\\repos\\swift-driver\\sandbox\\sandbox\\sandbox\\file2.swift": !dirty [1570318778, 0]
          "C:\\repos\\swift-driver\\sandbox\\sandbox\\sandbox\\main.swift": [1570083660, 0]
          "E:\\gazorp.swift": !private [0,0]
    """#
  }
  static var fineGrainedSourceFileDependencyGraph: String {
    #"""
    # Fine-grained v0
    ---
    allNodes:
      - key:
          kind:            sourceFileProvide
          aspect:          interface
          context:         ''
          name:            'C:\\Users\\owenvoorhees\\Desktop\\hello.swiftdeps'
        fingerprint:     85188db3503106210367dbcb7f5d1524
        sequenceNumber:  0
        defsIDependUpon: [ 30, 28, 24, 23, 27, 22, 21 ]
        isProvides:      true
      - key:
          kind:            sourceFileProvide
          aspect:          implementation
          context:         ''
          name:            'C:\\Users\\owenvoorhees\\Desktop\\hello.swiftdeps'
        fingerprint:     85188db3503106210367dbcb7f5d1524
        sequenceNumber:  1
        defsIDependUpon: [ 26, 25, 31, 20, 19, 29, 18 ]
        isProvides:      true
      - key:
          kind:            topLevel
          aspect:          interface
          context:         ''
          name:            Foo
        fingerprint:     8daabb8cdf69d8e8702b4788be12efd6
        sequenceNumber:  2
        defsIDependUpon: [ 0 ]
        isProvides:      true
      - key:
          kind:            topLevel
          aspect:          implementation
          context:         ''
          name:            Foo
        fingerprint:     8daabb8cdf69d8e8702b4788be12efd6
        sequenceNumber:  3
        defsIDependUpon: [  ]
        isProvides:      true
      - key:
          kind:            topLevel
          aspect:          interface
          context:         ''
          name:            a
        sequenceNumber:  4
        defsIDependUpon: [ 0 ]
        isProvides:      true
      - key:
          kind:            topLevel
          aspect:          implementation
          context:         ''
          name:            a
        sequenceNumber:  5
        defsIDependUpon: [  ]
        isProvides:      true
      - key:
          kind:            topLevel
          aspect:          interface
          context:         ''
          name:            y
        sequenceNumber:  6
        defsIDependUpon: [ 0 ]
        isProvides:      true
      - key:
          kind:            topLevel
          aspect:          implementation
          context:         ''
          name:            y
        sequenceNumber:  7
        defsIDependUpon: [  ]
        isProvides:      true
      - key:
          kind:            nominal
          aspect:          interface
          context:         SS
          name:            ''
        sequenceNumber:  8
        defsIDependUpon: [ 0 ]
        isProvides:      true
      - key:
          kind:            nominal
          aspect:          implementation
          context:         SS
          name:            ''
        sequenceNumber:  9
        defsIDependUpon: [  ]
        isProvides:      true
      - key:
          kind:            nominal
          aspect:          interface
          context:         5hello3FooV
          name:            ''
        fingerprint:     8daabb8cdf69d8e8702b4788be12efd6
        sequenceNumber:  10
        defsIDependUpon: [ 0 ]
        isProvides:      true
      - key:
          kind:            nominal
          aspect:          implementation
          context:         5hello3FooV
          name:            ''
        fingerprint:     8daabb8cdf69d8e8702b4788be12efd6
        sequenceNumber:  11
        defsIDependUpon: [  ]
        isProvides:      true
      - key:
          kind:            potentialMember
          aspect:          interface
          context:         SS
          name:            ''
        sequenceNumber:  12
        defsIDependUpon: [ 0 ]
        isProvides:      true
      - key:
          kind:            potentialMember
          aspect:          implementation
          context:         SS
          name:            ''
        sequenceNumber:  13
        defsIDependUpon: [  ]
        isProvides:      true
      - key:
          kind:            potentialMember
          aspect:          interface
          context:         5hello3FooV
          name:            ''
        fingerprint:     8daabb8cdf69d8e8702b4788be12efd6
        sequenceNumber:  14
        defsIDependUpon: [ 0 ]
        isProvides:      true
      - key:
          kind:            potentialMember
          aspect:          implementation
          context:         5hello3FooV
          name:            ''
        fingerprint:     8daabb8cdf69d8e8702b4788be12efd6
        sequenceNumber:  15
        defsIDependUpon: [  ]
        isProvides:      true
      - key:
          kind:            member
          aspect:          interface
          context:         SS
          name:            abc
        sequenceNumber:  16
        defsIDependUpon: [ 0 ]
        isProvides:      true
      - key:
          kind:            member
          aspect:          implementation
          context:         SS
          name:            abc
        sequenceNumber:  17
        defsIDependUpon: [  ]
        isProvides:      true
      - key:
          kind:            topLevel
          aspect:          interface
          context:         ''
          name:            StringLiteralType
        sequenceNumber:  18
        defsIDependUpon: [  ]
        isProvides:      false
      - key:
          kind:            topLevel
          aspect:          interface
          context:         ''
          name:            FloatLiteralType
        sequenceNumber:  19
        defsIDependUpon: [  ]
        isProvides:      false
      - key:
          kind:            topLevel
          aspect:          interface
          context:         ''
          name:            IntegerLiteralType
        sequenceNumber:  20
        defsIDependUpon: [  ]
        isProvides:      false
      - key:
          kind:            topLevel
          aspect:          interface
          context:         ''
          name:            String
        sequenceNumber:  21
        defsIDependUpon: [  ]
        isProvides:      false
      - key:
          kind:            topLevel
          aspect:          interface
          context:         ''
          name:            Int
        sequenceNumber:  22
        defsIDependUpon: [  ]
        isProvides:      false
      - key:
          kind:            externalDepend
          aspect:          interface
          context:         ''
          name:            'C:\\Users\\owenvoorhees\\Documents\\Development\\swift-source\\build\\Ninja-ReleaseAssert\\swift-macosx-x86_64\\lib\\swift\\macosx\\Swift.swiftmodule\\x86_64-apple-macos.swiftmodule'
        sequenceNumber:  23
        defsIDependUpon: [  ]
        isProvides:      false
      - key:
          kind:            externalDepend
          aspect:          interface
          context:         ''
          name:            'C:\\Users\\owenvoorhees\\Documents\\Development\\swift-source\\build\\Ninja-ReleaseAssert\\swift-macosx-x86_64\\lib\\swift\\macosx\\SwiftOnoneSupport.swiftmodule\\x86_64-apple-macos.swiftmodule'
        sequenceNumber:  24
        defsIDependUpon: [  ]
        isProvides:      false
      - key:
          kind:            nominal
          aspect:          interface
          context:         s35_ExpressibleByBuiltinIntegerLiteralP
          name:            ''
        sequenceNumber:  25
        defsIDependUpon: [  ]
        isProvides:      false
      - key:
          kind:            nominal
          aspect:          interface
          context:         s34_ExpressibleByBuiltinStringLiteralP
          name:            ''
        sequenceNumber:  26
        defsIDependUpon: [  ]
        isProvides:      false
      - key:
          kind:            member
          aspect:          interface
          context:         5hello3FooV
          name:            init
        sequenceNumber:  27
        defsIDependUpon: [  ]
        isProvides:      false
      - key:
          kind:            member
          aspect:          interface
          context:         SS
          name:            Int
        sequenceNumber:  28
        defsIDependUpon: [  ]
        isProvides:      false
      - key:
          kind:            member
          aspect:          interface
          context:         s35_ExpressibleByBuiltinIntegerLiteralP
          name:            init
        sequenceNumber:  29
        defsIDependUpon: [  ]
        isProvides:      false
      - key:
          kind:            member
          aspect:          interface
          context:         5hello3FooV
          name:            baz
        sequenceNumber:  30
        defsIDependUpon: [  ]
        isProvides:      false
      - key:
          kind:            member
          aspect:          interface
          context:         s34_ExpressibleByBuiltinStringLiteralP
          name:            init
        sequenceNumber:  31
        defsIDependUpon: [  ]
        isProvides:      false
    ...

    """#
  }
#endif
}
