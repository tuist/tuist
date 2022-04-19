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

    func test_load_template_options() throws {
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
        let options = try subject.loadTemplateOptions(
            templateName: "template",
            path: nil
        )

        // Then
        XCTAssertEqual(options.required, expectedOptions.required)
        XCTAssertEqual(options.optional, expectedOptions.optional)
    }

    func test_load_template_plugin_options() throws {
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
        let options = try subject.loadTemplateOptions(
            templateName: "PluginTemplate",
            path: nil
        )

        // Then
        XCTAssertEqual(options.required, expectedOptions.required)
        XCTAssertEqual(options.optional, expectedOptions.optional)
    }

    func test_fails_when_template_not_found() throws {
        let templateName = "template"
        XCTAssertThrowsSpecific(
            try subject.testRun(templateName: templateName),
            ScaffoldServiceError.templateNotFound(templateName, searchPaths: [])
        )
    }

    func test_fails_when_required_attribute_not_provided() throws {
        // Given
        templateLoader.loadTemplateStub = { _ in
            Template.test(attributes: [.required("required")])
        }

        templatesDirectoryLocator.templateDirectoriesStub = { _ in
            [try self.temporaryPath().appending(component: "template")]
        }

        // Then
        XCTAssertThrowsSpecific(
            try subject.testRun(),
            ScaffoldServiceError.attributeNotProvided("required")
        )
    }

    func test_optional_attribute_is_taken_from_template() throws {
        // Given
        templateLoader.loadTemplateStub = { _ in
            Template.test(attributes: [.optional("optional", default: "optionalValue")])
        }

        templatesDirectoryLocator.templateDirectoriesStub = { _ in
            [try self.temporaryPath().appending(component: "template")]
        }

        var generateAttributes: [String: String] = [:]
        templateGenerator.generateStub = { _, _, attributes in
            generateAttributes = attributes
        }

        // When
        try subject.testRun()

        // Then
        XCTAssertEqual(
            ["optional": "optionalValue"],
            generateAttributes
        )
    }

    func test_attributes_are_passed_to_generator() throws {
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

        var generateAttributes: [String: String] = [:]
        templateGenerator.generateStub = { _, _, attributes in
            generateAttributes = attributes
        }

        // When
        try subject.testRun(
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
    ) throws {
        try run(
            path: path,
            templateName: templateName,
            requiredTemplateOptions: requiredTemplateOptions,
            optionalTemplateOptions: optionalTemplateOptions
        )
    }
}
