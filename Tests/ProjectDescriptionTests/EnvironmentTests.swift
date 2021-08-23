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
            switch value {
            case .boolean(true):
                break
            default:
                XCTFail("Unexpected value. Got: \(value), expected: .boolean(true)")
            }
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
            switch value {
            case .boolean(false):
                break
            default:
                XCTFail("Unexpected value. Got: \(value), expected: .boolean(false)")
            }
        }
    }

    func test_stringValue() {
        let stringValue = UUID().uuidString
        let environment: [String: String] = [
            "0": stringValue,
        ]
        let value = Environment.value(for: "0", environment: environment)
        switch value {
        case .string(stringValue):
            break
        default:
            XCTFail("Unexpected value. Got: \(String(describing: value)), expected: .boolean(_)")
        }
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

        // mimicing the camel cased dynamic member format
        let value = Environment.value(for: "nameSuffix", environment: environment)
        switch value {
        case .boolean(false):
            break
        default:
            XCTFail("Unexpected value. Got: \(String(describing: value)), expected: .boolean(false)")
        }
    }

    func testNonPrefixedKeysAreFetchedIfPrefixedValueDoesNotExist() {
        let environment: [String: String] = [
            "NAME_SUFFIX": "1",
        ]

        // mimicing the camel cased dynamic member format
        let value = Environment.value(for: "nameSuffix", environment: environment)
        switch value {
        case .boolean(true):
            break
        default:
            XCTFail("Unexpected value. Got: \(String(describing: value)), expected: .boolean(true)")
        }
    }
}
