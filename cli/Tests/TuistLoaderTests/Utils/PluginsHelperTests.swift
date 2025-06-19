import Foundation
import TuistCore
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistTesting

final class PluginsHelperTests: TuistUnitTestCase {
    private var subject: ResourceSynthesizerPathLocator!

    override func setUp() {
        super.setUp()

        subject = ResourceSynthesizerPathLocator()
    }

    override func tearDown() {
        subject = nil

        super.tearDown()
    }

    func test_templatePath_when_plugin_not_found() async throws {
        await XCTAssertThrowsSpecific(
            try await subject.templatePath(
                for: "A",
                resourceName: "Strings",
                resourceSynthesizerPlugins: [.test(name: "B"), .test(name: "C")]
            ),
            ResourceSynthesizerPathLocatorError.pluginNotFound("A", ["B", "C"])
        )
    }

    func test_templatePath_when_template_does_not_exist() async throws {
        await XCTAssertThrowsSpecific(
            try await subject.templatePath(
                for: "A",
                resourceName: "Strings",
                resourceSynthesizerPlugins: [.test(name: "A")]
            ),
            ResourceSynthesizerPathLocatorError.resourceTemplateNotFound(name: "Strings.stencil", plugin: "A")
        )
    }

    func test_templatePath_when_template_exists() async throws {
        // Given
        let pluginPath = try temporaryPath()
        let templatePath = pluginPath.appending(component: "Strings.stencil")
        try fileHandler.touch(templatePath)

        // When
        let got = try await subject.templatePath(
            for: "A",
            resourceName: "Strings",
            resourceSynthesizerPlugins: [
                .test(
                    name: "A",
                    path: pluginPath
                ),
            ]
        )

        // Then
        XCTAssertEqual(
            got,
            templatePath
        )
    }

    func test_resourceTemplateNotFound_error() {
        XCTAssertEqual(
            ResourceSynthesizerPathLocatorError.resourceTemplateNotFound(name: "Strings.stencil", plugin: "A").description,
            "No template Strings.stencil found in a plugin A"
        )
    }

    func test_pluginNotFound_error() {
        XCTAssertEqual(
            ResourceSynthesizerPathLocatorError.pluginNotFound("A", ["B", "C"]).description,
            "Plugin A was not found. Available plugins: B, C"
        )
    }
}
