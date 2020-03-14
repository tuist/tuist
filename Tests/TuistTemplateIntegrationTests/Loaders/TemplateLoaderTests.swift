import Basic
import Foundation
import TuistSupport
import XCTest

@testable import TuistSupportTesting
@testable import TuistTemplate

final class TemplateLoaderTests: TuistTestCase {
    var subject: TemplateLoader!

    override func setUp() {
        super.setUp()
        subject = TemplateLoader()
    }

    override func tearDown() {
        super.tearDown()
        subject = nil
    }

    func test_loadTemplate() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let content = """
        import ProjectDescription
        
        let template = Template(
            description: "Template description"
        )
        """

        let manifestPath = temporaryPath.appending(component: "Template.swift")
        try content.write(to: manifestPath.url,
                          atomically: true,
                          encoding: .utf8)

        // When
        let got = try subject.loadTemplate(at: temporaryPath)

        // Then
        XCTAssertEqual(got.description, "Template description")
    }

    func test_load_invalidFormat() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let content = """
        import ABC
        let template
        """

        let manifestPath = temporaryPath.appending(component: "Template.swift")
        try content.write(to: manifestPath.url,
                          atomically: true,
                          encoding: .utf8)

        // When / Then
        XCTAssertThrowsError(
            try subject.loadTemplate(at: temporaryPath)
        )
    }

    func test_load_missingManifest() throws {
        let temporaryPath = try self.temporaryPath()
        XCTAssertThrowsSpecific(try subject.loadTemplate(at: temporaryPath),
                                TemplateLoaderError.manifestNotFound(temporaryPath.appending(components: "Template.swift")))
    }
}
