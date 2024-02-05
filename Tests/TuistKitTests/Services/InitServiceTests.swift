import Foundation
import TSCBasic
import TuistGraph
import TuistScaffold
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistLoaderTesting
@testable import TuistScaffoldTesting
@testable import TuistSupportTesting

final class InitServiceTests: TuistUnitTestCase {
    var subject: InitService!
    var templatesDirectoryLocator: MockTemplatesDirectoryLocator!
    var templateGenerator: MockTemplateGenerator!
    var templateLoader: MockTemplateLoader!
    var templateGitLoader: MockTemplateGitLoader!

    override func setUp() {
        super.setUp()
        templatesDirectoryLocator = MockTemplatesDirectoryLocator()
        templateGenerator = MockTemplateGenerator()
        templateLoader = MockTemplateLoader()
        templateGitLoader = MockTemplateGitLoader()
        subject = InitService(
            templateLoader: templateLoader,
            templatesDirectoryLocator: templatesDirectoryLocator,
            templateGenerator: templateGenerator,
            templateGitLoader: templateGitLoader
        )
    }

    override func tearDown() {
        subject = nil
        templatesDirectoryLocator = nil
        templateGenerator = nil
        templateLoader = nil
        templateGitLoader = nil
        super.tearDown()
    }

    func test_fails_when_directory_not_empty() throws {
        // Given
        let path = FileHandler.shared.currentPath
        try FileHandler.shared.touch(path.appending(component: "dummy"))

        // Then
        XCTAssertThrowsSpecific(try subject.testRun(), InitServiceError.nonEmptyDirectory(path))
    }

    func test_init_fails_when_template_not_found() throws {
        let templateName = "template"
        XCTAssertThrowsSpecific(try subject.testRun(templateName: templateName), InitServiceError.templateNotFound(templateName))
    }

    func test_init_default_when_no_template() throws {
        // Given
        let defaultTemplatePath = try temporaryPath().appending(component: "default")
        templatesDirectoryLocator.templateDirectoriesStub = { _ in
            [defaultTemplatePath]
        }
        let expectedAttributes: [String: TuistGraph.Template.Attribute.Value] = [
            "name": .string("Name"),
            "platform": .string("macOS"),
        ]
        var generatorAttributes: [String: TuistGraph.Template.Attribute.Value] = [:]
        templateGenerator.generateStub = { _, _, attributes in
            generatorAttributes = attributes
        }

        // When
        try subject.testRun(name: "Name", platform: "macos")

        // Then
        XCTAssertEqual(expectedAttributes, generatorAttributes)
    }

    func test_init_default_platform() throws {
        // Given
        let defaultTemplatePath = try temporaryPath().appending(component: "default")
        templatesDirectoryLocator.templateDirectoriesStub = { _ in
            [defaultTemplatePath]
        }
        let expectedAttributes: [String: TuistGraph.Template.Attribute.Value] = [
            "name": .string("Name"),
            "platform": .string("iOS"),
        ]
        var generatorAttributes: [String: TuistGraph.Template.Attribute.Value] = [:]
        templateGenerator.generateStub = { _, _, attributes in
            generatorAttributes = attributes
        }

        // When
        try subject.testRun(name: "Name")

        // Then
        XCTAssertEqual(expectedAttributes, generatorAttributes)
    }

    func test_load_git_template_attributes() async throws {
        // Given
        templateGitLoader.loadTemplateStub = { _ in
            Template(
                description: "test",
                attributes: [
                    .required("required"),
                    .optional("optional", default: .string("optionalValue")),
                ],
                items: []
            )
        }
        let expectedAttributes: [String: TuistGraph.Template.Attribute.Value] = [
            "name": .string("Name"),
            "platform": .string("macOS"),
            "required": .string("requiredValue"),
            "optional": .string("optionalValue"),
        ]
        var generatorAttributes: [String: TuistGraph.Template.Attribute.Value] = [:]
        templateGenerator.generateStub = { _, _, attributes in
            generatorAttributes = attributes
        }

        // When
        try subject.testRun(
            name: "Name",
            platform: "macos",
            templateName: "https://url/to/repo.git",
            requiredTemplateOptions: [
                "required": "requiredValue",
            ]
        )

        // Then
        XCTAssertEqual(expectedAttributes, generatorAttributes)
    }

    func test_optional_dictionary_attribute_is_taken_from_template() async throws {
        // Given
        let context: TuistGraph.Template.Attribute.Value = .dictionary([
            "key1": .string("value1"),
            "key2": .string("value2"),
        ])

        templateLoader.loadTemplateStub = { _ in
            Template.test(attributes: [
                .optional("optional", default: context),
            ])
        }

        let defaultTemplatePath = try temporaryPath().appending(component: "default")
        templatesDirectoryLocator.templateDirectoriesStub = { _ in
            [defaultTemplatePath]
        }

        let expectedAttributes: [String: TuistGraph.Template.Attribute.Value] = [
            "name": .string("Name"),
            "platform": .string("iOS"),
            "optional": context,
        ]

        var generatorAttributes: [String: TuistGraph.Template.Attribute.Value] = [:]
        templateGenerator.generateStub = { _, _, attributes in
            generatorAttributes = attributes
        }

        // When
        try subject.testRun(name: "Name")

        // Then
        XCTAssertEqual(expectedAttributes, generatorAttributes)
    }

    func test_optional_integer_attribute_is_taken_from_template() async throws {
        // Given
        let defaultIntegerValue: TuistGraph.Template.Attribute.Value = .integer(999)

        templateLoader.loadTemplateStub = { _ in
            Template.test(attributes: [
                .optional("optional", default: defaultIntegerValue),
            ])
        }

        let defaultTemplatePath = try temporaryPath().appending(component: "default")
        templatesDirectoryLocator.templateDirectoriesStub = { _ in
            [defaultTemplatePath]
        }

        let expectedAttributes: [String: TuistGraph.Template.Attribute.Value] = [
            "name": .string("Name"),
            "platform": .string("iOS"),
            "optional": defaultIntegerValue,
        ]

        var generatorAttributes: [String: TuistGraph.Template.Attribute.Value] = [:]
        templateGenerator.generateStub = { _, _, attributes in
            generatorAttributes = attributes
        }

        // When
        try subject.testRun(name: "Name")

        // Then
        XCTAssertEqual(expectedAttributes, generatorAttributes)
    }
}

extension InitService {
    func testRun(
        name: String? = nil,
        platform: String? = nil,
        path: String? = nil,
        templateName: String? = nil,
        requiredTemplateOptions: [String: String] = [:],
        optionalTemplateOptions: [String: String?] = [:]
    ) throws {
        try run(
            name: name,
            platform: platform,
            path: path,
            templateName: templateName,
            requiredTemplateOptions: requiredTemplateOptions,
            optionalTemplateOptions: optionalTemplateOptions
        )
    }
}
