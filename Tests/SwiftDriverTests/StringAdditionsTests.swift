//===--------- StringAdditionsTests.swift - String Additions Tests --------===//
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
import SwiftDriver
import TSCTestSupport

final class StringAdditionsTests: XCTestCase {

    func testBasicIdentifiers() {
        XCTAssertTrue("contains_Underscore".sd_isSwiftIdentifier)
        XCTAssertTrue("_startsWithUnderscore".sd_isSwiftIdentifier)
        XCTAssertTrue("contains_Number5".sd_isSwiftIdentifier)
        XCTAssertTrue("_1".sd_isSwiftIdentifier)
        XCTAssertTrue("contains$dollar".sd_isSwiftIdentifier)
            
        assertInvalidIdentifier("5startsWithNumber", expectedMessage:
            "Swift identifiers cannot start with a number")
			
        assertInvalidIdentifier("contains space", expectedMessage:
            "Swift identifiers cannot contains spaces")
			
        assertInvalidIdentifier("contains\nnewline", expectedMessage:
            "Swift identifiers cannot contain new line characters")
			
        assertInvalidIdentifier("contains\ttab", expectedMessage:
            "Swift identifiers cannot contain tab characters")
			
        assertInvalidIdentifier("contains_punctuation,.!?#", expectedMessage:
            ##"Swift identifiers cannot contain punctuation (like ",", ".", "!", "?", or "#")"##)
			
        assertInvalidIdentifier("$startsWithDollar", expectedMessage:
            #"Swift identifiers cannot start with a dollar sign ("$")"#)
			
        assertInvalidIdentifier("operators+-=*/^", expectedMessage:
            #"Swift identifiers cannot contain operators (like "+", "-", "=", "*", "/", or "^")"#)
			
        assertInvalidIdentifier("braces{}", expectedMessage:
            #"Swift identifiers cannot contain curly braces ("{" or "}")"#)
			
        assertInvalidIdentifier("angleBrackets<>", expectedMessage:
            #"Swift identifiers cannot contain parenthesis ("<" or ">")"#)
			
        assertInvalidIdentifier("parens()", expectedMessage:
            #"Swift identifiers cannot contain parenthesis ("(" or ")")"#)
			
        assertInvalidIdentifier("squareBrackets[]", expectedMessage:
            #"Swift identifiers cannot contain square brackets ("[" or "]")"#)
			
        assertInvalidIdentifier("<#some name#>", expectedMessage:
            "Swift identifiers cannot contain Xcode placeholders")
			
        assertInvalidIdentifier("", expectedMessage:
            "Swift identifiers cannot be empty")
			
        assertInvalidIdentifier("`$`", expectedMessage:
            "Swift identifiers cannot be only a dollar sign") // TODO: what's the exact rule here?
			
        assertInvalidIdentifier("backtick`", expectedMessage:
            "Swift identifiers cannot contain mis-matched backticks") // TODO: what's the exact rule here?
    }

    func testSwiftKeywordsAsIdentifiers() {
        XCTAssertTrue("import".sd_isSwiftIdentifier)
        XCTAssertTrue("func".sd_isSwiftIdentifier)
        XCTAssertTrue("var".sd_isSwiftIdentifier)
        XCTAssertTrue("typealias".sd_isSwiftIdentifier)
        XCTAssertTrue("class".sd_isSwiftIdentifier)
        XCTAssertTrue("struct".sd_isSwiftIdentifier)
        XCTAssertTrue("enum".sd_isSwiftIdentifier)
        XCTAssertTrue("associatedtype".sd_isSwiftIdentifier)
        XCTAssertTrue("prefix".sd_isSwiftIdentifier)
        XCTAssertTrue("infix".sd_isSwiftIdentifier)
        XCTAssertTrue("postfix".sd_isSwiftIdentifier)
        XCTAssertTrue("_".sd_isSwiftIdentifier)
    }

    func testUnicodeCharacters() {
        XCTAssertTrue("👨".sd_isSwiftIdentifier)
        XCTAssertFalse("❤️".sd_isSwiftIdentifier) // Multiple codepoints
        XCTAssertTrue("💑".sd_isSwiftIdentifier) // Single codepoint
        XCTAssertFalse("🙍🏻‍♂️".sd_isSwiftIdentifier) // Multiple codepoints
        XCTAssertTrue("你好".sd_isSwiftIdentifier)
        XCTAssertTrue("שלום".sd_isSwiftIdentifier)
        XCTAssertTrue("வணக்கம்".sd_isSwiftIdentifier)
        XCTAssertTrue("Γειά".sd_isSwiftIdentifier)
        XCTAssertTrue("яЛюблюСвифт".sd_isSwiftIdentifier)

        XCTAssertFalse(".́duh".sd_isSwiftIdentifier,
                       "Identifiers cannot start with combining chars")

        XCTAssertTrue("s̈pin̈al_tap̈".sd_isSwiftIdentifier,
                      "Combining characters can be used within identifiers")

        XCTAssertFalse("".sd_isSwiftIdentifier,
                       "Private-use characters aren't valid Swift identifiers")
    }
    
    private func assertInvalidIdentifier(
        _ invalidIdentifier: String,
        expectedMessage: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
			  XCTAssertThrows(try invalidIdentifier.sd_validateSwiftIdentifier()) { e in
					  guard let e = e as? InvalidSwiftIdentifierError else {
								XCTFail()
								return
						}
						XCTAssertEqual(e.message, expectedMesssage)
				}
    }
}
