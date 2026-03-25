import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Testing
import TuistConfigLoader
import TuistCore
import TuistLoader
import TuistPlugin
import TuistScaffold
import TuistSupport

@testable import TuistKit
@testable import TuistTesting

@Suite(.withMockedDependencies()) struct ScaffoldServiceTests {
    var subject: ScaffoldService!
    var templateLoader: MockTemplateLoading!
    var templatesDirectoryLocator: MockTemplatesDirectoryLocating!
    var templateGenerator: MockTemplateGenerating!
    var configLoader: MockConfigLoading!
    var pluginService: MockPluginService!

    init() {
        templateLoader = MockTemplateLoading()
        templatesDirectoryLocator = MockTemplatesDirectoryLocating()
        templateGenerator = MockTemplateGenerating()
        configLoader = MockConfigLoading()
        pluginService = MockPluginService()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)
        subject = ScaffoldService(
            templateLoader: templateLoader,
            templatesDirectoryLocator: templatesDirectoryLocator,
            templateGenerator: templateGenerator,
            configLoader: configLoader,
            pluginService: pluginService
        )
    }

    @Test(.inTemporaryDirectory) func load_template_options() async throws {
        // Given
        given(templateLoader)
            .loadTemplate(at: .any, plugins: .any)
            .willReturn(
                Template(
                    description: "test",
                    attributes: [
                        .required("required"),
                        .optional("optional", default: .string("")),
                    ],
                    items: []
                )
            )

        given(templatesDirectoryLocator)
            .templateDirectories(at: .any)
            .willReturn([try #require(FileSystem.temporaryTestDirectory).appending(component: "template")])

        let expectedOptions = (required: ["required"], optional: ["optional"])

        // When
        let options = try await subject.loadTemplateOptions(
            templateName: "template",
            path: nil
        )

        // Then
        #expect(options.required == expectedOptions.required)
        #expect(options.optional == expectedOptions.optional)
    }

    @Test(.inTemporaryDirectory) func load_template_plugin_options() async throws {
        // Given
        given(templateLoader)
            .loadTemplate(at: .any, plugins: .any)
            .willReturn(
                Template(
                    description: "test",
                    attributes: [
                        .required("required"),
                        .optional("optional", default: .string("")),
                    ],
                    items: []
                )
            )

        let expectedOptions = (required: ["required"], optional: ["optional"])
        let pluginTemplatePath = try #require(FileSystem.temporaryTestDirectory).appending(component: "PluginTemplate")

        pluginService.loadPluginsStub = { _ in
            Plugins.test(templatePaths: [pluginTemplatePath])
        }

        given(templatesDirectoryLocator)
            .templatePluginDirectories(at: .any)
            .willReturn([pluginTemplatePath])

        given(templatesDirectoryLocator)
            .templateDirectories(at: .any)
            .willReturn([])

        // When
        let options = try await subject.loadTemplateOptions(
            templateName: "PluginTemplate",
            path: nil
        )

        // Then
        #expect(options.required == expectedOptions.required)
        #expect(options.optional == expectedOptions.optional)
    }

    @Test func fails_when_template_not_found() async throws {
        let templateName = "template"
        given(templateLoader)
            .loadTemplate(at: .any, plugins: .any)
            .willReturn(
                Template.test(attributes: [.required("required")])
            )

        given(templatesDirectoryLocator)
            .templateDirectories(at: .any)
            .willReturn([])
        await #expect(throws: ScaffoldServiceError.templateNotFound(templateName, searchPaths: [])) {
            try await subject.testRun(templateName: templateName)
        }
    }

    @Test(.inTemporaryDirectory) func fails_when_required_attribute_not_provided() async throws {
        // Given
        given(templateLoader)
            .loadTemplate(at: .any, plugins: .any)
            .willReturn(
                Template.test(attributes: [.required("required")])
            )

        given(templatesDirectoryLocator)
            .templateDirectories(at: .any)
            .willReturn([try #require(FileSystem.temporaryTestDirectory).appending(component: "template")])

        // Then
        await #expect(throws: ScaffoldServiceError.attributeNotProvided("required")) {
            try await subject.testRun()
        }
    }

    @Test(.inTemporaryDirectory) func optional_attribute_is_taken_from_template() async throws {
        // Given
        given(templateLoader)
            .loadTemplate(at: .any, plugins: .any)
            .willReturn(
                Template.test(attributes: [.optional("optional", default: .string("optionalValue"))])
            )

        given(templatesDirectoryLocator)
            .templateDirectories(at: .any)
            .willReturn([try #require(FileSystem.temporaryTestDirectory).appending(component: "template")])

        given(templateGenerator)
            .generate(
                template: .any,
                to: .any,
                attributes: .any
            )
            .willReturn()

        // When
        try await subject.testRun()

        // Then
        verify(templateGenerator)
            .generate(
                template: .any,
                to: .any,
                attributes: .value(["optional": .string("optionalValue")])
            )
            .called(1)
    }

    @Test(.inTemporaryDirectory) func optional_dictionary_attribute_is_taken_from_template() async throws {
        // Given
        let context: Template.Attribute.Value = .dictionary([
            "key1": .string("value1"),
            "key2": .string("value2"),
        ])

        given(templateLoader)
            .loadTemplate(at: .any, plugins: .any)
            .willReturn(
                Template.test(attributes: [.optional("optional", default: context)])
            )

        given(templatesDirectoryLocator)
            .templateDirectories(at: .any)
            .willReturn([try #require(FileSystem.temporaryTestDirectory).appending(component: "template")])

        given(templateGenerator)
            .generate(
                template: .any,
                to: .any,
                attributes: .any
            )
            .willReturn()

        // When
        try await subject.testRun()

        // Then
        verify(templateGenerator)
            .generate(
                template: .any,
                to: .any,
                attributes: .value(["optional": context])
            )
            .called(1)
    }

    @Test(.inTemporaryDirectory) func optional_integer_attribute_is_taken_from_template() async throws {
        // Given
        let defaultIntegerValue: Template.Attribute.Value = .integer(999)

        given(templateLoader)
            .loadTemplate(at: .any, plugins: .any)
            .willReturn(
                Template.test(attributes: [.optional("optional", default: defaultIntegerValue)])
            )

        given(templatesDirectoryLocator)
            .templateDirectories(at: .any)
            .willReturn([try #require(FileSystem.temporaryTestDirectory).appending(component: "template")])

        given(templateGenerator)
            .generate(
                template: .any,
                to: .any,
                attributes: .any
            )
            .willReturn()

        // When
        try await subject.testRun()

        // Then
        verify(templateGenerator)
            .generate(
                template: .any,
                to: .any,
                attributes: .value(["optional": defaultIntegerValue])
            )
            .called(1)
    }

    @Test(.inTemporaryDirectory) func attributes_are_passed_to_generator() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)
        given(templateLoader)
            .loadTemplate(at: .any, plugins: .any)
            .willReturn(
                Template.test(attributes: [
                    .optional("optional", default: .string("")),
                    .required("required"),
                ])
            )

        given(templatesDirectoryLocator)
            .templateDirectories(at: .any)
            .willReturn([try #require(FileSystem.temporaryTestDirectory).appending(component: "template")])

        given(templateGenerator)
            .generate(
                template: .any,
                to: .any,
                attributes: .any
            )
            .willReturn()

        // When
        try await subject.testRun(
            requiredTemplateOptions: ["required": "requiredValue"],
            optionalTemplateOptions: ["optional": "optionalValue"]
        )

        // Then
        verify(templateGenerator)
            .generate(
                template: .any,
                to: .any,
                attributes: .value(
                    [
                        "optional": .string("optionalValue"),
                        "required": .string("requiredValue"),
                    ]
                )
            )
            .called(1)
    }
}

extension ScaffoldService {
    func testRun(
        path: String? = nil,
        templateName: String = "template",
        requiredTemplateOptions: [String: String] = [:],
        optionalTemplateOptions: [String: String] = [:]
    ) async throws {
        try await run(
            path: path,
            templateName: templateName,
            requiredTemplateOptions: requiredTemplateOptions,
            optionalTemplateOptions: optionalTemplateOptions
        )
    }
}
