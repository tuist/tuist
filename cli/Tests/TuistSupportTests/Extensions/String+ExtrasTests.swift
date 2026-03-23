import Foundation
import TSCUtility
import Testing

@testable import TuistSupport
@testable import TuistTesting

struct StringExtrasTests {
    @Test
    func test_camelized() {
        // Given
        let subject = "Framework-iOSResources"

        // When
        let got = subject.camelized

        // Then
        #expect(got == "frameworkIOSResources")
    }

    @Test
    func test_camelized_edge_cases() {
        // Given
        let subject = "_1Flow"

        // When
        let got = subject.camelized

        // Then
        #expect(got == "_1Flow")
    }

    @Test
    func test_to_valid_swift_identifier_starting_with_lowercase_letter() {
        // Given
        let subject = "classname"

        // When
        let got = subject.toValidSwiftIdentifier()

        // Then
        #expect(got == "Classname")
    }

    @Test
    func test_to_valid_swift_identifier_string_starting_with_numbers() {
        // Given
        let subject = "123invalidName"

        // When
        let got = subject.toValidSwiftIdentifier()

        // Then
        #expect(got == "_123invalidName")
    }

    @Test
    func test_to_valid_swift_identifier_string_with_special_characters() {
        // Given
        let subject = "class$name"

        // When
        let got = subject.toValidSwiftIdentifier()

        // Then
        #expect(got == "ClassName")
    }

    @Test
    func test_to_valid_swift_identifier_string_is_already_a_valid_swift_identifier() {
        // Given
        let subject = "ValidClassName"

        // When
        let got = subject.toValidSwiftIdentifier()

        // Then
        #expect(got == "ValidClassName")
    }

    @Test
    func test_to_valid_in_bundle_identifier_when_string_is_already_valid() {
        // Given
        let subject = "TestBundleIdentifier.tuist"

        // When
        let got = subject.toValidInBundleIdentifier()

        // Then
        #expect(got == "TestBundleIdentifier.tuist")
    }

    @Test
    func test_to_valid_in_bundle_identifier_when_string_contains_under_bars() {
        // Given
        let subject = "_test_bundle_identifier_"

        // When
        let got = subject.toValidInBundleIdentifier()

        // Then
        #expect(got == "-test-bundle-identifier-")
    }

    @Test
    func test_to_valid_in_bundle_identifier_when_string_contains_special_characters() {
        // Given
        let subject = "$test+bundle@identifier"

        // When
        let got = subject.toValidInBundleIdentifier()

        // Then
        #expect(got == "-test-bundle-identifier")
    }

    @Test
    func test_to_valid_in_bundle_identifier_when_string_contains_white_spaces() {
        // Given
        let subject = "test  bundle  identifier"

        // When
        let got = subject.toValidInBundleIdentifier()

        // Then
        #expect(got == "test--bundle--identifier")
    }

    @Test
    func test_string_doesnt_match_GitURL_regex() {
        // Given
        let stringToEvaluate = "not a url string"

        // When
        let result = stringToEvaluate.isGitURL

        // Then
        #expect(!result)
    }

    @Test
    func test_string_does_match_http_GitURL_with_branch_regex() {
        // Given
        let stringToEvaluate = "https://github.com/tuist/ExampleTuistTemplate.git@develop"

        // When
        let result = stringToEvaluate.isGitURL

        // Then
        #expect(result)
    }

    @Test
    func test_string_does_match_http_GitURL_without_branch_regex() {
        // Given
        let stringToEvaluate = "https://github.com/tuist/ExampleTuistTemplate.git"

        // When
        let result = stringToEvaluate.isGitURL

        // Then
        #expect(result)
    }

    @Test
    func test_string_does_match_ssh_GitURL_with_branch_regex() {
        // Given
        let stringToEvaluate = "git@github.com:user/repo.git@develop"

        // When
        let result = stringToEvaluate.isGitURL

        // Then
        #expect(result)
    }

    @Test
    func test_string_does_match_ssh_GitURL_without_branch_regex() {
        // Given
        let stringToEvaluate = "git@github.com:user/repo.git"

        // When
        let result = stringToEvaluate.isGitURL

        // Then
        #expect(result)
    }
}

struct StringsArrayTests {
    @Test
    func test_listed_when_no_elements() {
        // Given
        let list: [String] = []

        // When
        let got = list.listed()

        // Then
        #expect(got == "")
    }

    @Test
    func test_listed_when_only_one_element() {
        // Given
        let list = ["App"]

        // When
        let got = list.listed()

        // Then
        #expect(got == "App")
    }

    @Test
    func test_listed_when_two_elements() {
        // Given
        let list = ["App", "Tests"]

        // When
        let got = list.listed()

        // Then
        #expect(got == "App and Tests")
    }

    @Test
    func test_listed_when_more_than_two_elements() {
        // Given
        let list = ["App", "Tests", "Framework"]

        // When
        let got = list.listed()

        // Then
        #expect(got == "App, Tests, and Framework")
    }
}
