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

    func test_to_valid_swift_identifier() {
        // Test Case 1: String starting with lowercase letter
        let str1 = "classname"
        XCTAssertEqual(str1.toValidSwiftIdentifier(), "Classname", "Expected 'Classname'")

        // Test Case 2: String starting with numbers
        let str2 = "123invalidName"
        XCTAssertEqual(str2.toValidSwiftIdentifier(), "_123invalidName", "Expected '_123invalidName'")

        // Test Case 3: String is a Swift reserved word
        let str3 = "class"
        XCTAssertEqual(str3.toValidSwiftIdentifier(), "Class", "Expected 'Class'")

        // Test Case 4: String with special characters
        let str4 = "class$name"
        XCTAssertEqual(str4.toValidSwiftIdentifier(), "ClassName", "Expected 'ClassName'")

        // Test Case 5: String is already a valid Swift Identifier
        let str5 = "ValidClassName"
        XCTAssertEqual(str5.toValidSwiftIdentifier(), "ValidClassName", "Expected 'ValidClassName'")
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
