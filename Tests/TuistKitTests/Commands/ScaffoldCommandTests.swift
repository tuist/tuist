import Basic
import Foundation
import SPMUtility
import TuistCore
import TuistScaffold
import TuistSupport
import XCTest

@testable import TuistCoreTesting
@testable import TuistKit
@testable import TuistLoaderTesting
@testable import TuistScaffoldTesting
@testable import TuistSupportTesting

final class ScaffoldCommandTests: TuistUnitTestCase {
    var subject: ScaffoldCommand!
    var parser: ArgumentParser!
    var templateLoader: MockTemplateLoader!
    var templatesDirectoryLocator: MockTemplatesDirectoryLocator!
    var templateGenerator: MockTemplateGenerator!

    override func setUp() {
        super.setUp()
        parser = ArgumentParser.test()
        templateLoader = MockTemplateLoader()
        templatesDirectoryLocator = MockTemplatesDirectoryLocator()
        templateGenerator = MockTemplateGenerator()
        subject = ScaffoldCommand(parser: parser,
                                  templateLoader: templateLoader,
                                  templatesDirectoryLocator: templatesDirectoryLocator,
                                  templateGenerator: templateGenerator)
    }

    override func tearDown() {
        parser = nil
        subject = nil
        templateLoader = nil
        templatesDirectoryLocator = nil
        templateGenerator = nil
        super.tearDown()
    }

    func test_name() {
        XCTAssertEqual(ScaffoldCommand.command, "scaffold")
    }

    func test_overview() {
        XCTAssertEqual(ScaffoldCommand.overview, "Generates new project based on template.")
    }

    func test_fails_when_directory_not_empty() throws {
        // Given
        let path = FileHandler.shared.currentPath
        try FileHandler.shared.touch(path.appending(component: "dummy"))

        let result = try parser.parse([ScaffoldCommand.command, "template"])

        // Then
        XCTAssertThrowsSpecific(try subject.run(with: result), ScaffoldCommandError.nonEmptyDirectory(path))
    }

    func test_fails_when_template_not_found() throws {
        let templateName = "template"
        let result = try parser.parse([ScaffoldCommand.command, templateName])
        XCTAssertThrowsSpecific(try subject.run(with: result), ScaffoldCommandError.templateNotFound(templateName))
    }

    func test_adds_attributes_when_parsing() throws {
        // Given
        templateLoader.loadTemplateStub = { _ in
            Template(description: "test",
                     attributes: [.required("name")])
        }

        templatesDirectoryLocator.templateDirectoriesStub = { _ in
            [try self.temporaryPath().appending(component: "template")]
        }

        // When
        let result = try subject.parse(with: parser,
                                       arguments: [ScaffoldCommand.command, "template", "--name", "test"])

        // Then
        XCTAssertEqual(try result.get("--name"), "test")
    }

    func test_fails_when_attributes_not_added() throws {
        // Given
        templateLoader.loadTemplateStub = { _ in
            Template(description: "test")
        }

        templatesDirectoryLocator.templateDirectoriesStub = { _ in
            [try self.temporaryPath().appending(component: "template")]
        }

        // Then
        XCTAssertThrowsError(try subject.parse(with: parser,
                                               arguments: [ScaffoldCommand.command, "template", "--name", "Test"]))
    }
    
    func test_fails_when_required_attribute_not_provided() throws {
        // Given
        templateLoader.loadTemplateStub = { _ in
            Template.test(attributes: [.required("required")])
        }
        
        templatesDirectoryLocator.templateDirectoriesStub = { _ in
            [try self.temporaryPath().appending(component: "template")]
        }
        
        let arguments = [ScaffoldCommand.command, "template"]
        _ = try subject.parse(with: parser, arguments: arguments)
        
        // When
        let result = try parser.parse(arguments)
        
        // Then
        XCTAssertThrowsSpecific(try subject.run(with: result),
                                ScaffoldCommandError.attributeNotProvided("required"))
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
        
        let arguments = [ScaffoldCommand.command, "template"]
        _ = try subject.parse(with: parser, arguments: arguments)
        let result = try parser.parse(arguments)
        
        // When
        try subject.run(with: result)
        
        // Then
        XCTAssertEqual(["optional": "optionalValue"],
                       generateAttributes)
    }
    
    func test_attributes_are_passed_to_generator() throws {
        // Given
        templateLoader.loadTemplateStub = { _ in
            Template.test(attributes: [.optional("optional", default: ""),
                                       .required("required")])
        }
        
        templatesDirectoryLocator.templateDirectoriesStub = { _ in
            [try self.temporaryPath().appending(component: "template")]
        }
        
        var generateAttributes: [String: String] = [:]
        templateGenerator.generateStub = { _, _, attributes in
            generateAttributes = attributes
        }
        
        let arguments = [ScaffoldCommand.command, "template", "--optional", "optionalValue", "--required", "requiredValue"]
        _ = try subject.parse(with: parser, arguments: arguments)
        let result = try parser.parse(arguments)
        
        // When
        try subject.run(with: result)
        
        // Then
        XCTAssertEqual(["optional": "optionalValue",
                        "required": "requiredValue"],
                       generateAttributes)
    }
}
