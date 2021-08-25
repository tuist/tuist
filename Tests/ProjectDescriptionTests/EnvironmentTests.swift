import Foundation
import XCTest

@testable import ProjectDescription

final class EnvironmentTests: XCTestCase {
    func test_booleanTrueValues() throws {
        let environment: [String: String] = [
            "0": "1",
            "1": "true",
            "2": "TRUE",
            "3": "yes",
            "4": "YES",
        ]
        try environment.keys.forEach { key in
            let value = try XCTUnwrap(Environment.value(for: key, environment: environment))
            XCTAssertEqual(value, .boolean(true))
        }
    }

    func test_booleanFalseValues() throws {
        let environment: [String: String] = [
            "0": "0",
            "1": "false",
            "2": "FALSE",
            "3": "no",
            "4": "NO",
        ]
        try environment.keys.forEach { key in
            let value = try XCTUnwrap(Environment.value(for: key, environment: environment))
            XCTAssertEqual(value, .boolean(false))
        }
    }

    func test_stringValue() {
        let stringValue = UUID().uuidString
        let environment: [String: String] = [
            "0": stringValue,
        ]
        let value = Environment.value(for: "0", environment: environment)
        XCTAssertEqual(value, .string(stringValue))
    }

    func test_unknownKeysReturnNil() {
        let environment: [String: String] = [
            "0": "0",
        ]
        let value = Environment.value(for: "1", environment: environment)
        XCTAssertNil(value)
    }

    func testValueChecksForTuistPrefixedValuesFirst() {
        let environment: [String: String] = [
            "TUIST_NAME_SUFFIX": "0",
            "NAME_SUFFIX": "1",
        ]

        // mimicking the camel cased dynamic member format
        let value = Environment.value(for: "nameSuffix", environment: environment)
        XCTAssertEqual(value, .boolean(false))
    }

    func testNonPrefixedKeysAreFetchedIfPrefixedValueDoesNotExist() {
        let environment: [String: String] = [
            "NAME_SUFFIX": "1",
        ]

        // mimicking the camel cased dynamic member format
        let value = Environment.value(for: "nameSuffix", environment: environment)
        XCTAssertEqual(value, .boolean(true))
    }
}
