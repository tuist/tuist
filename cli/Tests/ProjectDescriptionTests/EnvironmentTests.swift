import Foundation
import Testing

@testable import ProjectDescription

struct EnvironmentTests {
    @Test func test_booleanTrueValues() throws {
        let environment: [String: String] = [
            "TUIST_0": "1",
            "TUIST_1": "true",
            "TUIST_2": "TRUE",
            "TUIST_3": "yes",
            "TUIST_4": "YES",
        ]
        for (index, _) in environment.enumerated() {
            let value = Environment.value(for: String(index), environment: environment)
            #expect(value.getBoolean(default: false))
        }
    }

    @Test func test_booleanFalseValues() throws {
        let environment: [String: String] = [
            "TUIST_0": "0",
            "TUIST_1": "false",
            "TUIST_2": "FALSE",
            "TUIST_3": "no",
            "TUIST_4": "NO",
        ]
        for (index, _) in environment.enumerated() {
            let value = Environment.value(for: String(index), environment: environment)
            #expect(!value.getBoolean(default: true))
        }
    }

    @Test func test_stringValue() {
        let stringValue = UUID().uuidString
        let environment: [String: String] = [
            "TUIST_0": stringValue,
            "TUIST_1": "1",
        ]
        for (index, _) in environment.enumerated() {
            let value = Environment.value(for: String(index), environment: environment)
            #expect(value.getString(default: "") == environment["TUIST_\(index)"])
        }
    }

    @Test func test_unknownKeysReturnNil() {
        let environment: [String: String] = [
            "TUIST_0": "0",
        ]
        let value = Environment.value(for: "1", environment: environment)
        #expect(value == nil)
    }
}
