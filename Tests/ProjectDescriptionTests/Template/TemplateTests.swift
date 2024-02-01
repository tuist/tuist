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
                .optional("aName", default: .string("defaultName")),
                .optional("bName", default: .string("")),
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
