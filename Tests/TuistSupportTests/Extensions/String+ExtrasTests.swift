import Foundation
import TSCBasic
import TSCUtility
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

    func test_camelized_edge_cases() {
        // Given
        let subject = "_1Flow"

        // When
        let got = subject.camelized

        // Then
        XCTAssertEqual(got, "_1Flow")
    }

    func test_to_valid_swift_identifier_starting_with_lowercase_letter() {
        // Given
        let subject = "classname"

        // When
        let got = subject.toValidSwiftIdentifier()

        // Then
        XCTAssertEqual(got, "Classname")
    }

    func test_to_valid_swift_identifier_string_starting_with_numbers() {
        // Given
        let subject = "123invalidName"

        // When
        let got = subject.toValidSwiftIdentifier()

        // Then
        XCTAssertEqual(got, "_123invalidName")
    }

    func test_to_valid_swift_identifier_string_with_special_characters() {
        // Given
        let subject = "class$name"

        // When
        let got = subject.toValidSwiftIdentifier()

        // Then
        XCTAssertEqual(got, "ClassName")
    }

    func test_to_valid_swift_identifier_string_is_already_a_valid_swift_identifier() {
        // Given
        let subject = "ValidClassName"

        // When
        let got = subject.toValidSwiftIdentifier()

        // Then
        XCTAssertEqual(got, "ValidClassName")
    }

    func test_string_doesnt_match_GitURL_regex() {
        // Given
        let stringToEvaluate = "not a url string"

        // When
        let result = stringToEvaluate.isGitURL

        // Then
        XCTAssertFalse(result)
    }

    func test_string_does_match_http_GitURL_with_branch_regex() {
        // Given
        let stringToEvaluate = "https://github.com/tuist/ExampleTuistTemplate.git@develop"

        // When
        let result = stringToEvaluate.isGitURL

        // Then
        XCTAssertTrue(result)
    }

    func test_string_does_match_http_GitURL_without_branch_regex() {
        // Given
        let stringToEvaluate = "https://github.com/tuist/ExampleTuistTemplate.git"

        // When
        let result = stringToEvaluate.isGitURL

        // Then
        XCTAssertTrue(result)
    }

    func test_string_does_match_ssh_GitURL_with_branch_regex() {
        // Given
        let stringToEvaluate = "git@github.com:user/repo.git@develop"

        // When
        let result = stringToEvaluate.isGitURL

        // Then
        XCTAssertTrue(result)
    }

    func test_string_does_match_ssh_GitURL_without_branch_regex() {
        // Given
        let stringToEvaluate = "git@github.com:user/repo.git"

        // When
        let result = stringToEvaluate.isGitURL

        // Then
        XCTAssertTrue(result)
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
