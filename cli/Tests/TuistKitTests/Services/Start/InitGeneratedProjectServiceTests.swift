import Foundation
import Mockable
import TuistCore
import TuistLoader
import TuistScaffold
import TuistSupport
import TuistTesting
import XCTest

@testable import TuistKit

final class InitGeneratedProjectServiceTests: TuistUnitTestCase {
    private var subject: InitGeneratedProjectService!
    private var templatesDirectoryLocator: MockTemplatesDirectoryLocating!
    private var templateGenerator: MockTemplateGenerating!
    private var templateLoader: MockTemplateLoading!
    private var templateGitLoader: MockTemplateGitLoader!

    override func setUp() {
        super.setUp()
        templatesDirectoryLocator = MockTemplatesDirectoryLocating()
        templateGenerator = MockTemplateGenerating()
        templateLoader = MockTemplateLoading()
        templateGitLoader = MockTemplateGitLoader()
        subject = InitGeneratedProjectService(
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

    func test_init_default_when_no_template() async throws {
        // Given
        let defaultTemplatePath = try temporaryPath().appending(component: "default")
        given(templatesDirectoryLocator)
            .templateDirectories(at: .any)
            .willReturn([defaultTemplatePath])

        let expectedAttributes: [String: Template.Attribute.Value] = [
            "name": .string("Name"),
            "platform": .string("macOS"),
            "tuist_version": .string(Constants.version),
            "class_name": .string("Name"),
            "bundle_identifier": .string("Name"),
        ]
        given(templateGenerator)
            .generate(
                template: .any,
                to: .any,
                attributes: .any
            )
            .willReturn()
        given(templateLoader)
            .loadTemplate(at: .any, plugins: .any)
            .willReturn(.test())

        // When
        try await subject.testRun(name: "Name", platform: "macos")

        // Then
        verify(templateGenerator)
            .generate(
                template: .any,
                to: .any,
                attributes: .value(expectedAttributes)
            )
            .called(1)
    }

    func test_init_default_platform() async throws {
        // Given
        let defaultTemplatePath = try temporaryPath().appending(component: "default")
        given(templatesDirectoryLocator)
            .templateDirectories(at: .any)
            .willReturn([defaultTemplatePath])

        let expectedAttributes: [String: Template.Attribute.Value] = [
            "name": .string("Name"),
            "platform": .string("iOS"),
            "tuist_version": .string(Constants.version),
            "class_name": .string("Name"),
            "bundle_identifier": .string("Name"),
        ]
        given(templateGenerator)
            .generate(
                template: .any,
                to: .any,
                attributes: .any
            )
            .willReturn()
        given(templateLoader)
            .loadTemplate(at: .any, plugins: .any)
            .willReturn(.test())

        // When
        try await subject.testRun(name: "Name")

        // Then
        verify(templateGenerator)
            .generate(
                template: .any,
                to: .any,
                attributes: .value(expectedAttributes)
            )
            .called(1)
    }

    func test_init_default_with_unusual_name() async throws {
        // Given
        let defaultTemplatePath = try temporaryPath().appending(component: "default")
        given(templatesDirectoryLocator)
            .templateDirectories(at: .any)
            .willReturn([defaultTemplatePath])

        let expectedAttributes: [String: TuistCore.Template.Attribute.Value] = [
            "name": .string("unusual name"),
            "platform": .string("iOS"),
            "tuist_version": .string(Constants.version),
            "class_name": .string("UnusualName"),
            "bundle_identifier": .string("unusual-name"),
        ]
        given(templateGenerator)
            .generate(
                template: .any,
                to: .any,
                attributes: .any
            )
            .willReturn()
        given(templateLoader)
            .loadTemplate(at: .any, plugins: .any)
            .willReturn(.test())

        // When
        try await subject.testRun(name: "unusual name")

        // Then
        verify(templateGenerator)
            .generate(
                template: .any,
                to: .any,
                attributes: .value(expectedAttributes)
            )
            .called(1)
    }
}

extension InitGeneratedProjectService {
    func testRun(
        name: String? = nil,
        platform: String? = nil,
        path: String? = nil
    ) async throws {
        try await run(
            name: name,
            platform: platform,
            path: path
        )
    }
}
