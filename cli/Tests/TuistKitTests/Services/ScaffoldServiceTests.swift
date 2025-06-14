import Foundation
import Mockable
import TuistCore
import TuistLoader
import TuistPlugin
import TuistScaffold
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistTesting

final class ScaffoldServiceTests: TuistUnitTestCase {
    var subject: ScaffoldService!
    var templateLoader: MockTemplateLoading!
    var templatesDirectoryLocator: MockTemplatesDirectoryLocating!
    var templateGenerator: MockTemplateGenerating!
    var configLoader: MockConfigLoading!
    var pluginService: MockPluginService!

    override func setUp() {
        super.setUp()
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

    override func tearDown() {
        subject = nil
        templateLoader = nil
        templatesDirectoryLocator = nil
        templateGenerator = nil
        super.tearDown()
    }

    func test_load_template_options() async throws {
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
            .willReturn([try temporaryPath().appending(component: "template")])

        let expectedOptions = (required: ["required"], optional: ["optional"])

        // When
        let options = try await subject.loadTemplateOptions(
            templateName: "template",
            path: nil
        )

        // Then
        XCTAssertEqual(options.required, expectedOptions.required)
        XCTAssertEqual(options.optional, expectedOptions.optional)
    }

    func test_load_template_plugin_options() async throws {
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
        let pluginTemplatePath = try temporaryPath().appending(component: "PluginTemplate")

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
        XCTAssertEqual(options.required, expectedOptions.required)
        XCTAssertEqual(options.optional, expectedOptions.optional)
    }

    func test_fails_when_template_not_found() async throws {
        let templateName = "template"
        given(templateLoader)
            .loadTemplate(at: .any, plugins: .any)
            .willReturn(
                Template.test(attributes: [.required("required")])
            )

        given(templatesDirectoryLocator)
            .templateDirectories(at: .any)
            .willReturn([])
        await XCTAssertThrowsSpecific(
            try await subject.testRun(templateName: templateName),
            ScaffoldServiceError.templateNotFound(templateName, searchPaths: [])
        )
    }

    func test_fails_when_required_attribute_not_provided() async throws {
        // Given
        given(templateLoader)
            .loadTemplate(at: .any, plugins: .any)
            .willReturn(
                Template.test(attributes: [.required("required")])
            )

        given(templatesDirectoryLocator)
            .templateDirectories(at: .any)
            .willReturn([try temporaryPath().appending(component: "template")])

        // Then
        await XCTAssertThrowsSpecific(
            try await subject.testRun(),
            ScaffoldServiceError.attributeNotProvided("required")
        )
    }

    func test_optional_attribute_is_taken_from_template() async throws {
        // Given
        given(templateLoader)
            .loadTemplate(at: .any, plugins: .any)
            .willReturn(
                Template.test(attributes: [.optional("optional", default: .string("optionalValue"))])
            )

        given(templatesDirectoryLocator)
            .templateDirectories(at: .any)
            .willReturn([try temporaryPath().appending(component: "template")])

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

    func test_optional_dictionary_attribute_is_taken_from_template() async throws {
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
            .willReturn([try temporaryPath().appending(component: "template")])

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

    func test_optional_integer_attribute_is_taken_from_template() async throws {
        // Given
        let defaultIntegerValue: Template.Attribute.Value = .integer(999)

        given(templateLoader)
            .loadTemplate(at: .any, plugins: .any)
            .willReturn(
                Template.test(attributes: [.optional("optional", default: defaultIntegerValue)])
            )

        given(templatesDirectoryLocator)
            .templateDirectories(at: .any)
            .willReturn([try temporaryPath().appending(component: "template")])

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

    func test_attributes_are_passed_to_generator() async throws {
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
            .willReturn([try temporaryPath().appending(component: "template")])

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
