import Foundation
import TSCBasic
import XCTest
@testable import TuistCore
@testable import TuistSupportTesting

final class XcodeBuildArgumentTests: TuistUnitTestCase {
    func test_arguments_returns_the_right_value_when_sdk() {
        // Given
        let subject = XcodeBuildArgument.sdk("sdk")

        // When
        let got = subject.arguments

        // Then
        XCTAssertEqual(got, ["-sdk", "sdk"])
    }

    func test_arguments_returns_the_right_value_when_destination() {
        // Given
        let subject = XcodeBuildArgument.destination("destination")

        // When
        let got = subject.arguments

        // Then
        XCTAssertEqual(got, ["-destination", "destination"])
    }

    func test_arguments_returns_the_right_value_when_derivedDataPath() {
        // Given
        let path = AbsolutePath.root
        let subject = XcodeBuildArgument.derivedDataPath(path)

        // When
        let got = subject.arguments

        // Then
        XCTAssertEqual(got, ["-derivedDataPath", path.pathString])
    }

    func test_arguments_returns_the_right_value_when_xcarg() {
        // Given
        let subject = XcodeBuildArgument.xcarg("key", "value")

        // When
        let got = subject.arguments

        // Then
        XCTAssertEqual(got, ["key=value"])
    }

    func test_arguments_returns_the_right_value_when_xcarg_with_spaces() {
        // Given
        let subject = XcodeBuildArgument.xcarg("key", "value with spaces")

        // When
        let got = subject.arguments

        // Then
        XCTAssertEqual(got, ["key=\'value with spaces\'"])
    }

    func test_arguments_returns_the_right_value_when_retry_count() {
        // Given
        let subject = XcodeBuildArgument.retryCount(5)

        // When
        let got = subject.arguments

        // Then
        XCTAssertEqual(got, ["-retry-tests-on-failure", "-test-iterations", "6"])
    }
}
