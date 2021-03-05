//===--------------- IncrementalImportTests.swift - Swift Testing ---------===//
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

class HideAndShowFuncInStructAndExtensionTests: XCTestCase {
  func testHideAndShowFuncInStruct() throws {
    try HideAndShowFunc<InStructStep>.test()
  }
  func testHideAndShowFuncInExtension() throws {
    try HideAndShowFunc<InExtensionStep>.test()
  }
  func testHideAndShowFuncInBoth() throws {
    try HideAndShowFunc<BothStep>.test()
  }
}

fileprivate struct HideAndShowFunc<Step: HideAndShowStep>: TestProtocol {
  static var start: Step.State { FState.bothHidden as! Step.State }
  static var steps: [Step] { [.show, .hide, .show] }
}

fileprivate protocol HideAndShowStep: StepProtocol {
  associatedtype State = FState
  static var show: Self {get}
  static var hide: Self {get}
}
fileprivate extension HideAndShowStep {
  var expectingWithout: [Source] { to.allOriginals }
}


fileprivate enum InStructStep: String, HideAndShowStep {
  case hide, show

  var to: State {
    switch self {
    case .hide: return .bothHidden
    case .show: return .shownInStruct
    }
  }
  var expectingWith: [Source] {
    switch self {
    case .hide:
      return [.definesGeneralFuncsAndCallsFuncInStruct, .callsFuncInExtension, .instantiatesS, .importedWithoutPublicFuncs ]
    case .show:
      return [.definesGeneralFuncsAndCallsFuncInStruct, .callsFuncInExtension, .instantiatesS, .importedWithoutPublicFuncs]
    }
  }
}

fileprivate enum InExtensionStep: String, HideAndShowStep {
  case hide, show

  var to: State {
    switch self {
    case .hide: return .bothHidden
    case .show: return .shownInExtension
    }
  }
  var expectingWith: [Source] {
    switch self {
    case .hide: return [.definesGeneralFuncsAndCallsFuncInStruct, .noUseOfS, .callsFuncInExtension, .instantiatesS, .importedWithoutPublicFuncs]
    case .show: return [.definesGeneralFuncsAndCallsFuncInStruct, .noUseOfS, .callsFuncInExtension, .instantiatesS, .importedWithoutPublicFuncs]
    }
  }
}

fileprivate enum BothStep: String, HideAndShowStep {
  case hide, show

  var to: State {
    switch self {
    case .hide: return .bothHidden
    case .show: return .bothShown
    }
  }
  var expectingWith: [Source] {
    switch self {
    case .hide: return [.definesGeneralFuncsAndCallsFuncInStruct, .noUseOfS, .callsFuncInExtension, .instantiatesS, .importedWithoutPublicFuncs]
    case .show: return [.definesGeneralFuncsAndCallsFuncInStruct, .noUseOfS, .callsFuncInExtension, .instantiatesS, .importedWithoutPublicFuncs]
    }
  }
}

fileprivate enum FState: String, StateProtocol {
  case bothHidden, shownInStruct, shownInExtension, bothShown

  var jobs: [CompileJob<Module>] {
    switch self {
    case .bothHidden:        return .building(.importedModule, .mainModule)
    case .shownInStruct:     return Self.bothHidden.jobs.substituting(.importedFileWithPublicFuncInStruct)
    case .shownInExtension:  return Self.bothHidden.jobs.substituting(.importedFileWithPublicFuncInExtension)
    case .bothShown:         return Self.bothHidden.jobs.substituting(.importedFileWithPublicFuncInStructAndExtension)
    }
  }
}

fileprivate extension FState {
  enum Module: String, ModuleProtocol {
    case importedModule, mainModule

    var sources: [Source] {
      switch self {
      case .importedModule:  return [.importedWithoutPublicFuncs]
      case .mainModule:      return [.definesGeneralFuncsAndCallsFuncInStruct, .noUseOfS, .callsFuncInExtension, .instantiatesS]
      }
    }

    var imports: [Self] {
      switch self {
      case .importedModule:  return []
      case .mainModule:      return [.importedModule]
      }
    }

    var isLibrary: Bool {
      switch self {
      case .importedModule: return true
      case .mainModule:      return false
      }
    }
  }
}

fileprivate extension FState.Module {
  enum Source: String, SourceProtocol {
    typealias Module = FState.Module

    case importedWithoutPublicFuncs = "imported",
         importedFileWithPublicFuncInStruct,
         importedFileWithPublicFuncInExtension,
         importedFileWithPublicFuncInStructAndExtension,
         definesGeneralFuncsAndCallsFuncInStruct = "main",
         noUseOfS,
         callsFuncInExtension,
         instantiatesS

    var original: Self {
      switch self {
      case .importedFileWithPublicFuncInStruct,
           .importedFileWithPublicFuncInExtension,
           .importedFileWithPublicFuncInStructAndExtension:
        return .importedWithoutPublicFuncs
      default: return self
      }
    }

    var code: String {
      switch self {
      case .definesGeneralFuncsAndCallsFuncInStruct: return """
                  import \(Module.importedModule.name)
                  extension S {
                    static func inStruct<I: SignedInteger>(_ si: I) {
                      print("1: not public")
                    }
                    static func inExtension<I: SignedInteger>(_ si: I) {
                      print("2: not public")
                    }
                  }
                  S.inStruct(3)
    """
      case .noUseOfS: return """
                  import \(Module.importedModule.name)
                  func baz() { T.bar("asdf") }
    """
      case .callsFuncInExtension: return """
                  import \(Module.importedModule.name)
                  func fred() { S.inExtension(3) }
      """
      case .instantiatesS: return """
                 import \(Module.importedModule.name)
                 func late() { S() }
    """
      case .importedWithoutPublicFuncs: return """
                  public protocol PP {}
                  public struct S: PP {
                    public init() {}
                    // public // was commented out; should rebuild users of inStruct
                    static func inStruct(_ i: Int) {print("1: private")}
                    func fo() {}
                  }
                  public struct T {
                    public init() {}
                    public static func bar(_ s: String) {print(s)}
                  }
                  extension S {
                   // public
                   static func inExtension(_ i: Int) {print("2: private")}
                  }
    """
      case .importedFileWithPublicFuncInStruct: return """
                  public protocol PP {}
                  public struct S: PP {
                    public init() {}
                    public // was uncommented out; should rebuild users of inStruct
                    static func inStruct(_ i: Int) {print("1: private")}
                    func fo() {}
                  }
                  public struct T {
                    public init() {}
                    public static func bar(_ s: String) {print(s)}
                  }
                  extension S {
                   // public
                   static func inExtension(_ i: Int) {print("2: private")}
                  }
    """
      case .importedFileWithPublicFuncInExtension: return """
                  public protocol PP {}
                  public struct S: PP {
                    public init() {}
                    // public // was commented out; should rebuild users of inStruct
                    static func inStruct(_ i: Int) {print("1: private")}
                    func fo() {}
                  }
                  public struct T {
                    public init() {}
                    public static func bar(_ s: String) {print(s)}
                  }
                  extension S {
                   // public
                   static func inExtension(_ i: Int) {print("2: private")}
                  }
      """
      case .importedFileWithPublicFuncInStructAndExtension: return """
                  public protocol PP {}
                  public struct S: PP {
                    public init() {}
                    public
                    static func inStruct(_ i: Int) {print("1: private")}
                    func fo() {}
                  }
                  public struct T {
                    public init() {}
                    public static func bar(_ s: String) {print(s)}
                  }
                  extension S {
                   public  // was uncommented; should rebuild users of inExtension
                   static func inExtension(_ i: Int) {print("2: private")}
                  }
    """
      }
    }
  }
}
