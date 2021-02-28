import Foundation
import TuistSupportTesting
import XCTest

@testable import ProjectDescription

final class FileHeaderTemplateTests: XCTestCase {
    func test_toJSON() throws {
        XCTAssertCodableEqualToJson(
            FileHeaderTemplate.file("Path/To/Template"),
            #"{"file": [{"type": "relativeToManifest", "pathString": "Path/To/Template"}]}"#
        )
        XCTAssertCodableEqualToJson(
            FileHeaderTemplate.string("File Header Template"),
            #"{"string": ["File Header Template"]}"#
        )
        XCTAssertCodableEqualToJson(
            FileHeaderTemplate(stringLiteral: "File Header Template"),
            #"{"string": ["File Header Template"]}"#
        )
    }
}
