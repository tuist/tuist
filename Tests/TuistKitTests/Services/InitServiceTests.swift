import Foundation
import TSCBasic
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

    override func setUp() {
        super.setUp()
        templatesDirectoryLocator = MockTemplatesDirectoryLocator()
        templateGenerator = MockTemplateGenerator()
        templateLoader = MockTemplateLoader()
        subject = InitService(
            templateLoader: templateLoader,
            templatesDirectoryLocator: templatesDirectoryLocator,
            templateGenerator: templateGenerator
        )
    }

    override func tearDown() {
        subject = nil
        templatesDirectoryLocator = nil
        templateGenerator = nil
        templateLoader = nil
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
        let expectedAttributes = ["name": "Name", "platform": "macOS"]
        var generatorAttributes: [String: String] = [:]
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
        let expectedAttributes = ["name": "Name", "platform": "iOS"]
        var generatorAttributes: [String: String] = [:]
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
