import Foundation
import TSCBasic
import XCTest

@testable import TuistSupport
@testable import TuistSupportTesting

final class StringExtrasTests: TuistUnitTestCase {
    func test_camelized() {
        // Given
        let subject = "Framework-iOSResources"

        // When
        let got = subject.camelized

        // Then
        XCTAssertEqual(got, "frameworkIOSResources")
    }
}

final class StringsArrayTests: TuistUnitTestCase {
    func test_listed_when_no_elements() {
        // Given
        let list: [String] = []

        // When
        let got = list.listed()

        // Then
        XCTAssertEqual(got, "")
    }

    func test_listed_when_only_one_element() {
        // Given
        let list = ["App"]

        // When
        let got = list.listed()

        // Then
        XCTAssertEqual(got, "App")
    }

    func test_listed_when_two_elements() {
        // Given
        let list = ["App", "Tests"]

        // When
        let got = list.listed()

        // Then
        XCTAssertEqual(got, "App and Tests")
    }

    func test_listed_when_more_than_two_elements() {
        // Given
        let list = ["App", "Tests", "Framework"]

        // When
        let got = list.listed()

        // Then
        XCTAssertEqual(got, "App, Tests, and Framework")
    }
}
