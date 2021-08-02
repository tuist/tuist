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

    func test_unknownKeysReturnNil() {
        let environment: [String: String] = [
            "0": "0",
        ]
        let value = Environment.value(for: "1", environment: environment)
        XCTAssertNil(value)
    }
}
