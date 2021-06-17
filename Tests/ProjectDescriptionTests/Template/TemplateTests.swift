import ProjectDescription
import TuistSupportTesting
import XCTest

class TemplateTests: XCTestCase {
    func test_template_codable() throws {
        // Given
        let template = Template(
            description: "",
            attributes: [
                .required("name"),
                .optional("aName", default: "defaultName"),
                .optional("bName", default: ""),
            ],
            items: [
                .string(path: "static.swift", contents: "content"),
                .file(path: "generated.swift", templatePath: "generate.swift"),
                .directory(path: "destinationFolder", sourcePath: "sourceFolder"),
            ]
        )

        // Then
        XCTAssertCodable(template)
    }
}
