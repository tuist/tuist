import Foundation
import Path
import Testing
@testable import TuistCore
@testable import TuistTesting

struct XcodeBuildArgumentTests {
    @Test func arguments_returns_the_right_value_when_sdk() {
        // Given
        let subject = XcodeBuildArgument.sdk("sdk")

        // When
        let got = subject.arguments

        // Then
        #expect(got == ["-sdk", "sdk"])
    }

    @Test func arguments_returns_the_right_value_when_destination() {
        // Given
        let subject = XcodeBuildArgument.destination("destination")

        // When
        let got = subject.arguments

        // Then
        #expect(got == ["-destination", "destination"])
    }

    @Test func arguments_returns_the_right_value_when_derivedDataPath() {
        // Given
        let path = AbsolutePath.root
        let subject = XcodeBuildArgument.derivedDataPath(path)

        // When
        let got = subject.arguments

        // Then
        #expect(got == ["-derivedDataPath", path.pathString])
    }

    @Test func arguments_returns_the_right_value_when_xcarg() {
        // Given
        let subject = XcodeBuildArgument.xcarg("key", "value")

        // When
        let got = subject.arguments

        // Then
        #expect(got == ["key=value"])
    }

    @Test func arguments_returns_the_right_value_when_xcarg_with_spaces() {
        // Given
        let subject = XcodeBuildArgument.xcarg("key", "value with spaces")

        // When
        let got = subject.arguments

        // Then
        #expect(got == ["key=\'value with spaces\'"])
    }

    @Test func arguments_returns_the_right_value_when_retry_count() {
        // Given
        let subject = XcodeBuildArgument.retryCount(5)

        // When
        let got = subject.arguments

        // Then
        #expect(got == ["-retry-tests-on-failure", "-test-iterations", "6"])
    }
}
