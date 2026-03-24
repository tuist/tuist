import FileSystemTesting
import Mockable
import Testing
import TuistCore
import TuistLoader
import TuistPlugin
import TuistScaffold
import TuistTesting

@testable import TuistKit

struct ListServiceTests {
    private var subject: ListService!
    private var pluginService: MockPluginService!
    private var templateLoader: MockTemplateLoading!
    private var templatesDirectoryLocator: MockTemplatesDirectoryLocating!

    init() {
        pluginService = MockPluginService()
        templateLoader = MockTemplateLoading()
        templatesDirectoryLocator = MockTemplatesDirectoryLocating()
        subject = ListService(
            pluginService: pluginService,
            templatesDirectoryLocator: templatesDirectoryLocator,
            templateLoader: templateLoader
        )
    }

    @Test func lists_available_templates_table_format() async throws {
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
            TuistTest.expectLogs(expectedOutput, at: .notice)
        }
    }

    @Test func lists_available_templates_json_format() async throws {
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
            TuistTest.expectLogs(expectedOutput, at: .notice)
        }
    }

    @Test func lists_available_templates_with_plugins() async throws {
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
            TuistTest.expectLogs(expectedOutput, at: .notice)
        }
    }
}
