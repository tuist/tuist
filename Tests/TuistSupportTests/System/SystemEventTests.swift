import Foundation
import XCTest
@testable import TuistSupport
@testable import TuistSupportTesting

final class SystemEventTests: TuistUnitTestCase {
    func test_value_when_standardOutput() {
        // Given
        let value = "test"
        let subject = SystemEvent<String>.standardOutput(value)

        // Then
        XCTAssertEqual(subject.value, value)
    }

    func test_value_when_standardError() {
        // Given
        let value = "test"
        let subject = SystemEvent<String>.standardError(value)

        // Then
        XCTAssertEqual(subject.value, value)
    }

    func test_mapToString_when_standardOutput() {
        // Given
        let value = "test"
        let data = value.data(using: .utf8)!
        let subject = SystemEvent<Data>.standardOutput(data)

        // When
        let got = subject.mapToString()

        // Then
        XCTAssertEqual(got, .standardOutput(value))
    }

    func test_mapToString_when_standardError() {
        // Given
        let value = "test"
        let data = value.data(using: .utf8)!
        let subject = SystemEvent<Data>.standardError(data)

        // When
        let got = subject.mapToString()

        // Then
        XCTAssertEqual(got, .standardError(value))
    }

    func test_isStandardOuptut_when_standardOutput() {
        // Given
        let value = "test"
        let data = value.data(using: .utf8)!
        let subject = SystemEvent<Data>.standardOutput(data)

        // When
        let got = subject.isStandardOutput

        // Then
        XCTAssertTrue(got)
    }

    func test_isStandardError_when_standardError() {
        // Given
        let value = "test"
        let data = value.data(using: .utf8)!
        let subject = SystemEvent<Data>.standardError(data)

        // When
        let got = subject.isStandardError

        // Then
        XCTAssertTrue(got)
    }

    func test_isStandardError_when_standardOutput() {
        // Given
        let value = "test"
        let data = value.data(using: .utf8)!
        let subject = SystemEvent<Data>.standardOutput(data)

        // When
        let got = subject.isStandardError

        // Then
        XCTAssertFalse(got)
    }

    func test_isStandardOuptut_when_standardError() {
        // Given
        let value = "test"
        let data = value.data(using: .utf8)!
        let subject = SystemEvent<Data>.standardError(data)

        // When
        let got = subject.isStandardOutput

        // Then
        XCTAssertFalse(got)
    }
}
