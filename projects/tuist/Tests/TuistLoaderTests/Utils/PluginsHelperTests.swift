import Foundation
import TSCBasic
import TuistSupport
import XCTest

@testable import TuistCoreTesting
@testable import TuistLoader
@testable import TuistSupportTesting

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

    func test_templatePath_when_plugin_not_found() throws {
        XCTAssertThrowsSpecific(
            try subject.templatePath(
                for: "A",
                resourceName: "Strings",
                resourceSynthesizerPlugins: [.test(name: "B"), .test(name: "C")]
            ),
            ResourceSynthesizerPathLocatorError.pluginNotFound("A", ["B", "C"])
        )
    }

    func test_templatePath_when_template_does_not_exist() throws {
        XCTAssertThrowsSpecific(
            try subject.templatePath(
                for: "A",
                resourceName: "Strings",
                resourceSynthesizerPlugins: [.test(name: "A")]
            ),
            ResourceSynthesizerPathLocatorError.resourceTemplateNotFound(name: "Strings.stencil", plugin: "A")
        )
    }

    func test_templatePath_when_template_exists() throws {
        // Given
        let pluginPath = try temporaryPath()
        let templatePath = pluginPath.appending(component: "Strings.stencil")
        try fileHandler.touch(templatePath)

        // When / Then
        XCTAssertEqual(
            try subject.templatePath(
                for: "A",
                resourceName: "Strings",
                resourceSynthesizerPlugins: [
                    .test(
                        name: "A",
                        path: pluginPath
                    ),
                ]
            ),
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
