import FileSystem
import FileSystemTesting
import Foundation
import Testing
import TuistCore
import TuistSupport

@testable import TuistLoader
@testable import TuistTesting

struct PluginsHelperTests {
    private let subject: ResourceSynthesizerPathLocator

    init() {
        subject = ResourceSynthesizerPathLocator()
    }

    @Test func templatePath_when_plugin_not_found() async throws {
        await #expect(throws: ResourceSynthesizerPathLocatorError.pluginNotFound("A", ["B", "C"])) {
            try await subject.templatePath(
                for: "A",
                resourceName: "Strings",
                resourceSynthesizerPlugins: [.test(name: "B"), .test(name: "C")]
            )
        }
    }

    @Test func templatePath_when_template_does_not_exist() async throws {
        await #expect(throws: ResourceSynthesizerPathLocatorError.resourceTemplateNotFound(
            name: "Strings.stencil",
            plugin: "A"
        )) {
            try await subject.templatePath(
                for: "A",
                resourceName: "Strings",
                resourceSynthesizerPlugins: [.test(name: "A")]
            )
        }
    }

    @Test(.inTemporaryDirectory) func templatePath_when_template_exists() async throws {
        // Given
        let pluginPath = try #require(FileSystem.temporaryTestDirectory)
        let templatePath = pluginPath.appending(component: "Strings.stencil")
        try FileHandler.shared.touch(templatePath)

        // When
        let got = try await subject.templatePath(
            for: "A",
            resourceName: "Strings",
            resourceSynthesizerPlugins: [
                .test(name: "A", path: pluginPath),
            ]
        )

        // Then
        #expect(got == templatePath)
    }

    @Test func resourceTemplateNotFound_error() {
        #expect(
            ResourceSynthesizerPathLocatorError.resourceTemplateNotFound(name: "Strings.stencil", plugin: "A").description ==
                "No template Strings.stencil found in a plugin A"
        )
    }

    @Test func pluginNotFound_error() {
        #expect(
            ResourceSynthesizerPathLocatorError.pluginNotFound("A", ["B", "C"]).description ==
                "Plugin A was not found. Available plugins: B, C"
        )
    }
}
