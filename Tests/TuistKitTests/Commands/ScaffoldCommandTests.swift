import Basic
import Foundation
import SPMUtility
import TuistSupport
import TuistTemplate
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting
@testable import TuistTemplateTesting

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

        let result = try parser.parse([ScaffoldCommand.command])

        // Then
        XCTAssertThrowsSpecific(try subject.run(with: result), ScaffoldCommandError.nonEmptyDirectory(path))
    }
    
    func test_template_found() throws {
        // Given
        let templateName = "template"
        let templatePath = try temporaryPath().appending(component: templateName)
        templatesDirectoryLocator.templateDirectoriesStub = {
            [templatePath]
        }
        var generateSourcePath: AbsolutePath?
        templateGenerator.generateStub = { sourcePath, _, _ in
            generateSourcePath = sourcePath
        }
        let result = try parser.parse([ScaffoldCommand.command, templateName])
        
        // When
        try subject.run(with: result)
        
        // Then
        XCTAssertEqual(generateSourcePath, templatePath)
    }
    
    func test_fails_when_template_not_found() throws {
        let templateName = "template"
        let result = try parser.parse([ScaffoldCommand.command, templateName])
        XCTAssertThrowsSpecific(try subject.run(with: result), ScaffoldCommandError.templateNotFound(templateName))
    }
    
    func test_generate_not_run_when_list() throws {
        // Given
        var didGenerate = false
        templateGenerator.generateStub = { _, _, _ in
            didGenerate = true
        }
        let result = try parser.parse([ScaffoldCommand.command, "--list", "template"])
        
        // When
        try subject.run(with: result)
        
        // Then
        XCTAssertFalse(didGenerate)
    }
}
