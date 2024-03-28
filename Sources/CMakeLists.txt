# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_subdirectory(CSwiftScan)
add_subdirectory(SwiftOptions)
add_subdirectory(SwiftDriver)
add_subdirectory(SwiftDriverExecution)
add_subdirectory(swift-build-sdk-interfaces)
add_subdirectory(swift-driver)
add_subdirectory(swift-help)

if(SWIFT_DRIVER_BUILD_TOOLS)
  add_subdirectory(makeOptions)
endif()
