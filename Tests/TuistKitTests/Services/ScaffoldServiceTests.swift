import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistGraphTesting
import TuistScaffold
import TuistSupport
import XCTest

@testable import TuistCoreTesting
@testable import TuistKit
@testable import TuistLoaderTesting
@testable import TuistPluginTesting
@testable import TuistScaffoldTesting
@testable import TuistSupportTesting

final class ScaffoldServiceTests: TuistUnitTestCase {
    var subject: ScaffoldService!
    var templateLoader: MockTemplateLoader!
    var templatesDirectoryLocator: MockTemplatesDirectoryLocator!
    var templateGenerator: MockTemplateGenerator!
    var configLoader: MockConfigLoader!
    var pluginService: MockPluginService!

    override func setUp() {
        super.setUp()
        templateLoader = MockTemplateLoader()
        templatesDirectoryLocator = MockTemplatesDirectoryLocator()
        templateGenerator = MockTemplateGenerator()
        configLoader = MockConfigLoader()
        pluginService = MockPluginService()
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
        templateLoader.loadTemplateStub = { _ in
            Template(
                description: "test",
                attributes: [
                    .required("required"),
                    .optional("optional", default: ""),
                ],
                items: []
            )
        }

        templatesDirectoryLocator.templateDirectoriesStub = { _ in
            [try self.temporaryPath().appending(component: "template")]
        }

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
        templateLoader.loadTemplateStub = { _ in
            Template(
                description: "test",
                attributes: [
                    .required("required"),
                    .optional("optional", default: ""),
                ],
                items: []
            )
        }

        let expectedOptions = (required: ["required"], optional: ["optional"])
        let pluginTemplatePath = try temporaryPath().appending(component: "PluginTemplate")

        pluginService.loadPluginsStub = { _ in
            Plugins.test(templatePaths: [pluginTemplatePath])
        }

        templatesDirectoryLocator.templatePluginDirectoriesStub = { _ in
            [pluginTemplatePath]
        }

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
        await XCTAssertThrowsSpecific(
            try await subject.testRun(templateName: templateName),
            ScaffoldServiceError.templateNotFound(templateName, searchPaths: [])
        )
    }

    func test_fails_when_required_attribute_not_provided() async throws {
        // Given
        templateLoader.loadTemplateStub = { _ in
            Template.test(attributes: [.required("required")])
        }

        templatesDirectoryLocator.templateDirectoriesStub = { _ in
            [try self.temporaryPath().appending(component: "template")]
        }

        // Then
        await XCTAssertThrowsSpecific(
            try await subject.testRun(),
            ScaffoldServiceError.attributeNotProvided("required")
        )
    }

    func test_optional_attribute_is_taken_from_template() async throws {
        // Given
        templateLoader.loadTemplateStub = { _ in
            Template.test(attributes: [.optional("optional", default: "optionalValue")])
        }

        templatesDirectoryLocator.templateDirectoriesStub = { _ in
            [try self.temporaryPath().appending(component: "template")]
        }

        var generateAttributes: [String: AnyHashable] = [:]
        templateGenerator.generateStub = { _, _, attributes in
            generateAttributes = attributes
        }

        // When
        try await subject.testRun()

        // Then
        XCTAssertEqual(
            ["optional": "optionalValue"],
            generateAttributes
        )
    }
    
    func test_optional_dictionary_attribute_is_taken_from_template() async throws {
        
        // Given
        struct Env: Hashable {
            let key: String
            let value: String
        }
        
        let context = [
            "envs": [
                Env(key: "key1", value: "value1"),
                Env(key: "key2", value: "value2"),
            ]
        ]
        
        templateLoader.loadTemplateStub = { _ in
            Template.test(attributes: [.optional("optional", default: context)])
        }

        templatesDirectoryLocator.templateDirectoriesStub = { _ in
            [try self.temporaryPath().appending(component: "template")]
        }

        var generateAttributes: [String: AnyHashable] = [:]
        templateGenerator.generateStub = { _, _, attributes in
            generateAttributes = attributes
        }

        // When
        try await subject.testRun()

        // Then
        XCTAssertEqual(
            ["optional": context],
            generateAttributes
        )
    }
    
    func test_optional_integer_attribute_is_taken_from_template() async throws {
        
        // Given
        let defaultIntegerValue: Int = 999
        
        templateLoader.loadTemplateStub = { _ in
            Template.test(attributes: [.optional("optional", default: defaultIntegerValue)])
        }

        templatesDirectoryLocator.templateDirectoriesStub = { _ in
            [try self.temporaryPath().appending(component: "template")]
        }

        var generateAttributes: [String: AnyHashable] = [:]
        templateGenerator.generateStub = { _, _, attributes in
            generateAttributes = attributes
        }

        // When
        try await subject.testRun()

        // Then
        XCTAssertEqual(
            ["optional": defaultIntegerValue],
            generateAttributes
        )
    }

    func test_attributes_are_passed_to_generator() async throws {
        // Given
        templateLoader.loadTemplateStub = { _ in
            Template.test(attributes: [
                .optional("optional", default: ""),
                .required("required"),
            ])
        }

        templatesDirectoryLocator.templateDirectoriesStub = { _ in
            [try self.temporaryPath().appending(component: "template")]
        }

        var generateAttributes: [String: AnyHashable] = [:]
        templateGenerator.generateStub = { _, _, attributes in
            generateAttributes = attributes
        }

        // When
        try await subject.testRun(
            requiredTemplateOptions: ["required": "requiredValue"],
            optionalTemplateOptions: ["optional": "optionalValue"]
        )

        // Then
        XCTAssertEqual(
            [
                "optional": "optionalValue",
                "required": "requiredValue",
            ],
            generateAttributes
        )
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
