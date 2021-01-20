import TSCBasic
import TuistGraph
import TuistGraphTesting
import XCTest

@testable import TuistCore
@testable import TuistKit
@testable import TuistLoaderTesting
@testable import TuistScaffoldTesting
@testable import TuistSupportTesting

final class ListServiceTests: TuistUnitTestCase {
    var subject: ListService!
    var templateLoader: MockTemplateLoader!
    var templatesDirectoryLocator: MockTemplatesDirectoryLocator!

    override func setUp() {
        super.setUp()
        templateLoader = MockTemplateLoader()
        templatesDirectoryLocator = MockTemplatesDirectoryLocator()
        subject = ListService(templatesDirectoryLocator: templatesDirectoryLocator,
                              templateLoader: templateLoader)
    }

    override func tearDown() {
        subject = nil
        templateLoader = nil
        templatesDirectoryLocator = nil
        super.tearDown()
    }

    func test_lists_available_templates_table_format() throws {
        // Given
        let expectedTemplates = ["template", "customTemplate"]
        let expectedOutput = """
        Name            Description
        ──────────────  ───────────
        template        description
        customTemplate  description
        """

        templatesDirectoryLocator.templateDirectoriesStub = { _ in
            try expectedTemplates.map(self.temporaryPath().appending)
        }

        templateLoader.loadTemplateStub = { _ in
            Template(description: "description")
        }

        // When
        try subject.run(path: nil, outputFormat: .table)

        // Then
        XCTAssertPrinterContains(expectedOutput, at: .info, ==)
    }

    func test_lists_available_templates_json_format() throws {
        // Given
        let expectedTemplates = ["template", "customTemplate"]
        let expectedOutput = """
        [
          {
            "description": "description",
            "name": "template"
          },
          {
            "description": "description",
            "name": "customTemplate"
          }
        ]
        """

        templatesDirectoryLocator.templateDirectoriesStub = { _ in
            try expectedTemplates.map(self.temporaryPath().appending)
        }

        templateLoader.loadTemplateStub = { _ in
            Template(description: "description")
        }

        // When
        try subject.run(path: nil, outputFormat: .json)

        // Then
        XCTAssertPrinterContains(expectedOutput, at: .info, ==)
    }
}
