import Foundation
import Testing
import TuistTesting

@testable import ProjectDescription

struct FileHeaderTemplateTests {
    @Test func test_file_header_template_toJSON() throws {
        #expect(try isCodableRoundTripable(FileHeaderTemplate.file("Path/To/Template")))
        #expect(try isCodableRoundTripable(FileHeaderTemplate.string("File Header Template")))
        #expect(try isCodableRoundTripable(FileHeaderTemplate(stringLiteral: "File Header Template")))
    }

    @Test func test_file_header_template_from_literal() {
        #expect(FileHeaderTemplate.string("value") == "value")

        let value = "value"

        #expect(FileHeaderTemplate.string("value") == "\(value)")
    }
}
