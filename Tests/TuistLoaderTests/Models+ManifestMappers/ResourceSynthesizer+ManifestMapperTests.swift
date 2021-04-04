import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistLoaderTesting
import TuistSupportTesting
import XCTest

@testable import TuistLoader

final class ResourceSynthesizerManifestMapperTests: TuistUnitTestCase {
    private var pluginsTemplatePathHelper: MockTemplatePathPluginsHelper!

    override func setUp() {
        super.setUp()

        pluginsTemplatePathHelper = MockTemplatePathPluginsHelper()
    }

    override func tearDown() {
        pluginsTemplatePathHelper = nil

        super.tearDown()
    }

    func test_from_when_default_strings() throws {
        // Given
        let manifestDirectory = try temporaryPath()

        // When
        let got = try ResourceSynthesizer.from(
            manifest: .strings(),
            generatorPaths: GeneratorPaths(manifestDirectory: manifestDirectory),
            plugins: .none,
            pluginsTemplatePathHelper: pluginsTemplatePathHelper
        )

        // Then
        XCTAssertEqual(
            got,
            .init(
                parser: .strings,
                extensions: ["strings", "stringsdict"],
                template: .defaultTemplate("Strings")
            )
        )
    }

    func test_from_when_plists_file() throws {
        // Given
        let manifestDirectory = try temporaryPath()

        // When
        let got = try ResourceSynthesizer.from(
            manifest: .plists(templatePath: "Template.stencil"),
            generatorPaths: GeneratorPaths(manifestDirectory: manifestDirectory),
            plugins: .none,
            pluginsTemplatePathHelper: pluginsTemplatePathHelper
        )

        // Then
        XCTAssertEqual(
            got,
            .init(
                parser: .plists,
                extensions: ["plist"],
                template: .file(manifestDirectory.appending(component: "Template.stencil"))
            )
        )
    }

    func test_from_when_assets_plugin() throws {
        // Given
        let manifestDirectory = try temporaryPath()
        var invokedPluginNames: [String] = []
        var invokedResourceNames: [String] = []
        var invokedResourceSynthesizerPlugins: [ResourceSynthesizerPlugin] = []
        pluginsTemplatePathHelper.templatePathStub = { pluginName, resourceName, resourceSynthesizerPlugins in
            invokedPluginNames.append(pluginName)
            invokedResourceNames.append(resourceName)
            invokedResourceSynthesizerPlugins.append(contentsOf: resourceSynthesizerPlugins)
            return manifestDirectory.appending(component: "PluginTemplate.stencil")
        }

        // When
        let got = try ResourceSynthesizer.from(
            manifest: .assets(plugin: "Plugin"),
            generatorPaths: GeneratorPaths(manifestDirectory: manifestDirectory),
            plugins: .test(
                resourceSynthesizers: [
                    .test(name: "Plugin"),
                ]
            ),
            pluginsTemplatePathHelper: pluginsTemplatePathHelper
        )

        // Then
        XCTAssertEqual(
            got,
            .init(
                parser: .assets,
                extensions: ["xcassets"],
                template: .file(manifestDirectory.appending(component: "PluginTemplate.stencil"))
            )
        )
        XCTAssertEqual(
            invokedPluginNames,
            ["Plugin"]
        )
        XCTAssertEqual(
            invokedResourceNames,
            ["Assets"]
        )
        XCTAssertEqual(
            invokedResourceSynthesizerPlugins,
            [.test(name: "Plugin")]
        )
    }
}
