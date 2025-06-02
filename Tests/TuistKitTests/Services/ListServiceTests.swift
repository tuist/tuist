import Mockable
import TuistCore
import TuistLoader
import TuistPlugin
import TuistScaffold
import TuistTesting
import XCTest

@testable import TuistKit

final class ListServiceTests: TuistUnitTestCase {
    private var subject: ListService!
    private var pluginService: MockPluginService!
    private var templateLoader: MockTemplateLoading!
    private var templatesDirectoryLocator: MockTemplatesDirectoryLocating!

    override func setUp() {
        super.setUp()
        pluginService = MockPluginService()
        templateLoader = MockTemplateLoading()
        templatesDirectoryLocator = MockTemplatesDirectoryLocating()
        subject = ListService(
            pluginService: pluginService,
            templatesDirectoryLocator: templatesDirectoryLocator,
            templateLoader: templateLoader
        )
    }

    override func tearDown() {
        subject = nil
        pluginService = nil
        templateLoader = nil
        templatesDirectoryLocator = nil
        super.tearDown()
    }

    func test_lists_available_templates_table_format() async throws {
        try await withMockedDependencies {
            // Given
            let expectedTemplates = ["template", "customTemplate"]
            let expectedOutput = """
            Name            Description
            ──────────────  ───────────
            template        description
            customTemplate  description
            """

            given(templatesDirectoryLocator)
                .templateDirectories(at: .any)
                .willReturn(try expectedTemplates.map(temporaryPath().appending))

            given(templateLoader)
                .loadTemplate(at: .any, plugins: .any)
                .willReturn(
                    Template(description: "description", items: [])
                )

            // When
            try await subject.run(path: nil, outputFormat: .table)

            // Then
            XCTAssertPrinterContains(expectedOutput, at: .notice, ==)
        }
    }

    func test_lists_available_templates_json_format() async throws {
        try await withMockedDependencies {
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

            given(templatesDirectoryLocator)
                .templateDirectories(at: .any)
                .willReturn(try expectedTemplates.map(temporaryPath().appending))

            given(templateLoader)
                .loadTemplate(at: .any, plugins: .any)
                .willReturn(
                    Template(description: "description", items: [])
                )

            // When
            try await subject.run(path: nil, outputFormat: .json)

            // Then
            XCTAssertPrinterContains(expectedOutput, at: .notice, ==)
        }
    }

    func test_lists_available_templates_with_plugins() async throws {
        try await withMockedDependencies {
            // Given
            let expectedTemplates = ["template", "customTemplate", "pluginTemplate"]
            let expectedOutput = """
            Name            Description
            ──────────────  ───────────
            template        description
            customTemplate  description
            pluginTemplate  description
            """

            let pluginTemplatePath = try temporaryPath().appending(component: "PluginTemplate")
            pluginService.loadPluginsStub = { _ in
                Plugins.test(templatePaths: [pluginTemplatePath])
            }

            given(templatesDirectoryLocator)
                .templateDirectories(at: .any)
                .willReturn(try expectedTemplates.map(temporaryPath().appending))

            given(templateLoader)
                .loadTemplate(at: .any, plugins: .any)
                .willReturn(
                    Template(description: "description", items: [])
                )

            // When
            try await subject.run(path: nil, outputFormat: .table)

            // Then
            XCTAssertPrinterContains(expectedOutput, at: .notice, ==)
        }
    }
}
