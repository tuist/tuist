import Foundation
import Path
import Testing
@testable import XcodeGraph

struct InfoPlistTests {
    @Test func codable_file() throws {
        // Given
        let subject = InfoPlist.file(path: try AbsolutePath(validating: "/path/to/file"))

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(InfoPlist.self, from: data)
        #expect(subject == decoded)
    }

    @Test func codable_dictionary() throws {
        // Given
        let subject = InfoPlist.dictionary([
            "key1": "value1",
            "key2": "value2",
            "key3": "value3",
        ])

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(InfoPlist.self, from: data)
        #expect(subject == decoded)
    }

    @Test func path_when_file() throws {
        // Given
        let path = try AbsolutePath(validating: "/path/Info.list")
        let subject: InfoPlist = .file(path: path)

        // Then
        #expect(subject.path == path)
    }

    @Test func expressive_by_string_literal() throws {
        // Given
        let subject: InfoPlist = "/path/Info.list"

        // Then
        #expect(subject.path == try AbsolutePath(validating: "/path/Info.list"))
    }

    @Test func expressive_by_string_literal_using_build_variable() {
        // Given
        let subject1: InfoPlist = "$(CONFIGURATION)/Info.list"
        let subject2: InfoPlist = "${CONFIGURATION}/Info.list"

        // Then
        #expect(subject1 == .variable("$(CONFIGURATION)/Info.list", configuration: nil))
        #expect(subject2 == .variable("${CONFIGURATION}/Info.list", configuration: nil))
    }
}
