import TemplateDescription
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
            files: [
                .static(path: "static.swift", contents: "content"),
                .generated(path: "generated.swift", generateFilePath: "generate.swift")
            ],
            directories: [
                "{{ name }}",
                "directory"
        ])
            

        // Then
        XCTAssertCodable(template)
    }
}
