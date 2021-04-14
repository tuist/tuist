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
    private var resourceSynthesizerPathLocator: MockResourceSynthesizerPathLocator!

    override func setUp() {
        super.setUp()

        resourceSynthesizerPathLocator = MockResourceSynthesizerPathLocator()
    }

    override func tearDown() {
        resourceSynthesizerPathLocator = nil

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
            resourceSynthesizerPathLocator: resourceSynthesizerPathLocator
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

    func test_from_when_default_strings_and_custom_template_defined() throws {
        // Given
        let manifestDirectory = try temporaryPath()
        var gotResourceName: String?
        resourceSynthesizerPathLocator.templatePathResourceStub = { resourceName, path in
            gotResourceName = resourceName
            return path.appending(component: "Template.stencil")
        }

        // When
        let got = try ResourceSynthesizer.from(
            manifest: .strings(),
            generatorPaths: GeneratorPaths(manifestDirectory: manifestDirectory),
            plugins: .none,
            resourceSynthesizerPathLocator: resourceSynthesizerPathLocator
        )

        // Then
        XCTAssertEqual(
            got,
            .init(
                parser: .strings,
                extensions: ["strings", "stringsdict"],
                template: .file(manifestDirectory.appending(component: "Template.stencil"))
            )
        )
        XCTAssertEqual(gotResourceName, "Strings")
    }

    func test_from_when_assets_plugin() throws {
        // Given
        let manifestDirectory = try temporaryPath()
        var invokedPluginNames: [String] = []
        var invokedResourceNames: [String] = []
        var invokedResourceSynthesizerPlugins: [PluginResourceSynthesizer] = []
        resourceSynthesizerPathLocator.templatePathStub = { pluginName, resourceName, resourceSynthesizerPlugins in
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
            resourceSynthesizerPathLocator: resourceSynthesizerPathLocator
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
