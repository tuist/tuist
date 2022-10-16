import Foundation
import XCTest

@testable import ProjectDescription

final class EnvironmentTests: XCTestCase {
    func test_booleanTrueValues() throws {
        let environment: [String: String] = [
            "TUIST_0": "1",
            "TUIST_1": "true",
            "TUIST_2": "TRUE",
            "TUIST_3": "yes",
            "TUIST_4": "YES",
        ]
        environment.enumerated().forEach { index, _ in
            let value = Environment.value(for: String(index), environment: environment)
            XCTAssertTrue(value.getBoolean(default: false))
        }
    }

    func test_booleanFalseValues() throws {
        let environment: [String: String] = [
            "TUIST_0": "0",
            "TUIST_1": "false",
            "TUIST_2": "FALSE",
            "TUIST_3": "no",
            "TUIST_4": "NO",
        ]
        environment.enumerated().forEach { index, _ in
            let value = Environment.value(for: String(index), environment: environment)
            XCTAssertFalse(value.getBoolean(default: true))
        }
    }

    func test_stringValue() {
        let stringValue = UUID().uuidString
        let environment: [String: String] = [
            "TUIST_0": stringValue,
            "TUIST_1": "1",
        ]
        environment.enumerated().forEach { index, pair in
            let value = Environment.value(for: String(index), environment: environment)
            XCTAssertEqual(value.getString(default: ""), pair.value)
        }
    }

    func test_unknownKeysReturnNil() {
        let environment: [String: String] = [
            "TUIST_0": "0",
        ]
        let value = Environment.value(for: "1", environment: environment)
        XCTAssertNil(value)
    }
}
