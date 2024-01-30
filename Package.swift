// swift-tools-version:5.7

import PackageDescription
import class Foundation.ProcessInfo

let macOSPlatform: SupportedPlatform
if let deploymentTarget = ProcessInfo.processInfo.environment["SWIFTPM_MACOS_DEPLOYMENT_TARGET"] {
    macOSPlatform = .macOS(deploymentTarget)
} else {
    macOSPlatform = .macOS(.v12)
}

let package = Package(
  name: "swift-driver",
  platforms: [
    macOSPlatform,
    .iOS(.v15),
  ],
  products: [
    .executable(
      name: "swift-driver",
      targets: ["swift-driver"]),
    .executable(
      name: "swift-help",
      targets: ["swift-help"]),
    .executable(
      name: "swift-build-sdk-interfaces",
      targets: ["swift-build-sdk-interfaces"]),
    .library(
      name: "SwiftDriver",
      targets: ["SwiftDriver"]),
    .library(
      name: "SwiftDriverDynamic",
      type: .dynamic,
      targets: ["SwiftDriver"]),
    .library(
      name: "SwiftOptions",
      targets: ["SwiftOptions"]),
    .library(
      name: "SwiftDriverExecution",
      targets: ["SwiftDriverExecution"]),
  ],
  targets: [

    /// C modules wrapper for _InternalLibSwiftScan.
    .target(name: "CSwiftScan",
            exclude: [ "CMakeLists.txt" ]),

    /// The driver library.
    .target(
      name: "SwiftDriver",
      dependencies: [
        "SwiftOptions",
        .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
        "CSwiftScan",
        .product(name: "Yams", package: "yams"),
      ],
      exclude: ["CMakeLists.txt"]),

    /// The execution library.
    .target(
      name: "SwiftDriverExecution",
      dependencies: [
        "SwiftDriver",
        .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core")
      ],
      exclude: ["CMakeLists.txt"]),

    /// Driver tests.
    .testTarget(
      name: "SwiftDriverTests",
      dependencies: ["SwiftDriver", "SwiftDriverExecution", "TestUtilities"]),

    /// IncrementalImport tests
    .testTarget(
      name: "IncrementalImportTests",
      dependencies: [
        "IncrementalTestFramework",
        "TestUtilities",
        .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
      ]),

    .target(
      name: "IncrementalTestFramework",
      dependencies: [ "SwiftDriver", "SwiftOptions", "TestUtilities" ],
      path: "Tests/IncrementalTestFramework",
      linkerSettings: [
        .linkedFramework("XCTest", .when(platforms: [.iOS, .macOS, .tvOS, .watchOS]))
      ]),

    .target(
      name: "TestUtilities",
      dependencies: ["SwiftDriver", "SwiftDriverExecution"],
      path: "Tests/TestUtilities"),

    /// The options library.
    .target(
      name: "SwiftOptions",
      dependencies: [
        .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
      ],
      exclude: ["CMakeLists.txt"]),
    .testTarget(
      name: "SwiftOptionsTests",
      dependencies: ["SwiftOptions"]),

    /// The primary driver executable.
    .executableTarget(
      name: "swift-driver",
      dependencies: ["SwiftDriverExecution", "SwiftDriver"],
      exclude: ["CMakeLists.txt"]),

    /// The help executable.
    .executableTarget(
      name: "swift-help",
      dependencies: [
        "SwiftOptions",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
      ],
      exclude: ["CMakeLists.txt"]),

    /// The help executable.
    .executableTarget(
      name: "swift-build-sdk-interfaces",
      dependencies: ["SwiftDriver", "SwiftDriverExecution"],
      exclude: ["CMakeLists.txt"]),

    /// The `makeOptions` utility (for importing option definitions).
    .executableTarget(
      name: "makeOptions",
      dependencies: []),
  ],
  cxxLanguageStandard: .cxx14
)

if ProcessInfo.processInfo.environment["SWIFT_DRIVER_LLBUILD_FWK"] == nil {
    if ProcessInfo.processInfo.environment["SWIFTCI_USE_LOCAL_DEPS"] == nil {
        package.dependencies += [
            .package(url: "https://github.com/apple/swift-llbuild.git", branch: "release/5.10"),
        ]
        package.targets.first(where: { $0.name == "SwiftDriverExecution" })!.dependencies += [
            .product(name: "llbuildSwift", package: "swift-llbuild"),
        ]
    } else {
        // In Swift CI, use a local path to llbuild to interoperate with tools
        // like `update-checkout`, which control the sources externally.
        package.dependencies += [
            .package(name: "llbuild", path: "../llbuild"),
        ]
        package.targets.first(where: { $0.name == "SwiftDriverExecution" })!.dependencies += [
            .product(name: "llbuildSwift", package: "llbuild"),
        ]
    }
}

if ProcessInfo.processInfo.environment["SWIFTCI_USE_LOCAL_DEPS"] == nil {
  package.dependencies += [
    .package(url: "https://github.com/apple/swift-tools-support-core.git", branch: "release/5.10"),
    .package(url: "https://github.com/jpsim/Yams.git", .upToNextMinor(from: "5.0.0")),
    // The 'swift-argument-parser' version declared here must match that
    // used by 'swift-package-manager' and 'sourcekit-lsp'. Please coordinate
    // dependency version changes here with those projects.
    .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMinor(from: "1.2.2")),
    ]
} else {
    package.dependencies += [
        .package(path: "../swift-tools-support-core"),
        .package(path: "../yams"),
        .package(path: "../swift-argument-parser"),
    ]
}
