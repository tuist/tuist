import Basic
import Foundation
import SPMUtility
import TuistSupport
import TuistScaffold
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting
@testable import TuistScaffoldTesting
@testable import TuistLoaderTesting

final class InitCommandTests: TuistUnitTestCase {
    var subject: InitCommand!
    var parser: ArgumentParser!
    var templatesDirectoryLocator: MockTemplatesDirectoryLocator!
    var templateGenerator: MockTemplateGenerator!
    var templateLoader: MockTemplateLoader!

    override func setUp() {
        super.setUp()
        parser = ArgumentParser.test()
        templatesDirectoryLocator = MockTemplatesDirectoryLocator()
        templateGenerator = MockTemplateGenerator()
        templateLoader = MockTemplateLoader()
        subject = InitCommand(parser: parser,
                              templatesDirectoryLocator: templatesDirectoryLocator,
                              templateGenerator: templateGenerator,
                              templateLoader: templateLoader)
    }

    override func tearDown() {
        parser = nil
        subject = nil
        templatesDirectoryLocator = nil
        templateGenerator = nil
        templateLoader = nil
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
        let expectedAttributes = ["name": "name", "platform": "macos"]
        let result = try parser.parse([InitCommand.command, "--name", "name", "--platform", "macos"])
        var generatorAttributes: [String: String] = [:]
        templateGenerator.generateStub = { _, _, attributes in
            generatorAttributes = attributes
        }

        // When
        try subject.run(with: result)

        // Then
        XCTAssertEqual(expectedAttributes, generatorAttributes)
    }

    func test_init_default_platform() throws {
        let defaultTemplatePath = try temporaryPath().appending(component: "default")
        templatesDirectoryLocator.templateDirectoriesStub = { _ in
            [defaultTemplatePath]
        }
        let expectedAttributes = ["name": "name", "platform": "ios"]
        let result = try parser.parse([InitCommand.command, "--name", "name"])
        var generatorAttributes: [String: String] = [:]
        templateGenerator.generateStub = { _, _, attributes in
            generatorAttributes = attributes
        }

        // When
        try subject.run(with: result)

        // Then
        XCTAssertEqual(expectedAttributes, generatorAttributes)
    }
}
