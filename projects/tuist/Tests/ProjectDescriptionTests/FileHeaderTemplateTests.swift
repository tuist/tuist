import Foundation
import TuistSupportTesting
import XCTest

@testable import ProjectDescription

final class FileHeaderTemplateTests: XCTestCase {
    func test_file_header_template_toJSON() {
        XCTAssertCodable(FileHeaderTemplate.file("Path/To/Template"))
        XCTAssertCodable(FileHeaderTemplate.string("File Header Template"))
        XCTAssertCodable(FileHeaderTemplate(stringLiteral: "File Header Template"))
    }

    func test_file_header_template_from_literal() {
        XCTAssertEqual(FileHeaderTemplate.string("value"), "value")

        let value = "value"

        XCTAssertEqual(FileHeaderTemplate.string("value"), "\(value)")
    }
}
