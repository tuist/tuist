import Basic
import Foundation
import SPMUtility
import TuistSupport
import TuistTemplate
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting
@testable import TuistTemplateTesting

final class InitCommandTests: TuistUnitTestCase {
    var subject: InitCommand!
    var parser: ArgumentParser!
    var templatesDirectoryLocator: MockTemplatesDirectoryLocator!
    var templateGenerator: MockTemplateGenerator!

    override func setUp() {
        super.setUp()
        parser = ArgumentParser.test()
        templatesDirectoryLocator = MockTemplatesDirectoryLocator()
        templateGenerator = MockTemplateGenerator()
        subject = InitCommand(parser: parser,
                              templatesDirectoryLocator: templatesDirectoryLocator,
                              templateGenerator: templateGenerator)
    }

    override func tearDown() {
        parser = nil
        subject = nil
        templatesDirectoryLocator = nil
        templateGenerator = nil
        super.tearDown()
    }

    func test_name() {
        XCTAssertEqual(InitCommand.command, "init")
    }

    func test_overview() {
        XCTAssertEqual(InitCommand.overview, "Bootstraps a project.")
    }
    
    func test_fails_when_directory_not_empty() throws {
        // Given
        let path = FileHandler.shared.currentPath
        try FileHandler.shared.touch(path.appending(component: "dummy"))

        let result = try parser.parse([InitCommand.command])

        // Then
        XCTAssertThrowsSpecific(try subject.run(with: result), InitCommandError.nonEmptyDirectory(path))
    }
    
    func test_template_found() throws {
        // Given
        let templateName = "template"
        let templatePath = try temporaryPath().appending(component: templateName)
        templatesDirectoryLocator.templateDirectoriesStub = { _ in
            [templatePath]
        }
        var generateSourcePath: AbsolutePath?
        templateGenerator.generateStub = { sourcePath, _, _ in
            generateSourcePath = sourcePath
        }
        let result = try parser.parse([InitCommand.command, "--template", templateName])
        
        // When
        try subject.run(with: result)
        
        // Then
        XCTAssertEqual(generateSourcePath, templatePath)
    }
    
    func test_init_fails_when_template_not_found() throws {
        let templateName = "template"
        let result = try parser.parse([InitCommand.command, "--template", templateName])
        XCTAssertThrowsSpecific(try subject.run(with: result), InitCommandError.templateNotFound(templateName))
    }
    
    func test_init_default_when_no_template() throws {
        // Given
        let defaultTemplatePath = try temporaryPath().appending(component: "default")
        templatesDirectoryLocator.templateDirectoriesStub = { _ in
            [defaultTemplatePath]
        }
        let attributes = ["--name", "name", "--platform", "macos"]
        let result = try parser.parse([InitCommand.command] + attributes)
        var generatorAttributes: [String] = []
        templateGenerator.generateStub = { _, _, attributes in
            generatorAttributes = attributes
        }
        
        // When
        try subject.run(with: result)
        
        // Then
        XCTAssertEqual(attributes, generatorAttributes)
    }
    
    func test_init_default_platform() throws {
        let defaultTemplatePath = try temporaryPath().appending(component: "default")
        templatesDirectoryLocator.templateDirectoriesStub = { _ in
            [defaultTemplatePath]
        }
        let attributes = ["--name", "name"]
        let result = try parser.parse([InitCommand.command] + attributes)
        var generatorAttributes: [String] = []
        templateGenerator.generateStub = { _, _, attributes in
            generatorAttributes = attributes
        }
        
        // When
        try subject.run(with: result)
        
        // Then
        XCTAssertEqual(attributes + ["--platform", "ios"], generatorAttributes)
    }
}
