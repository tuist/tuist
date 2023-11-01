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
    var subject: ResourceSynthesizerPathLocator!

    override func setUp() {
        super.setUp()

        resourceSynthesizerPathLocator = MockResourceSynthesizerPathLocator()
        subject = ResourceSynthesizerPathLocator(rootDirectoryLocator: RootDirectoryLocator())
    }

    override func tearDown() {
        resourceSynthesizerPathLocator = nil
        subject = nil
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
                parserOptions: [:],
                extensions: ["strings", "stringsdict"],
                template: .defaultTemplate("Strings")
            )
        )
    }

    func test_from_when_default_strings_with_parserOptions() throws {
        // Given
        let parserOptions: [String: ProjectDescription.ResourceSynthesizer.Parser.Option] = [
            "stringValue": "test",
            "intValue": 999,
            "boolValue": true,
            "doubleValue": 1.0,
        ]
        let manifestDirectory = try temporaryPath()

        // When
        let got = try ResourceSynthesizer.from(
            manifest: .strings(parserOptions: parserOptions),
            generatorPaths: GeneratorPaths(manifestDirectory: manifestDirectory),
            plugins: .none,
            resourceSynthesizerPathLocator: resourceSynthesizerPathLocator
        )

        // Then
        XCTAssertEqual(
            got,
            .init(
                parser: .strings,
                parserOptions: [
                    "stringValue": "test",
                    "intValue": 999,
                    "boolValue": true,
                    "doubleValue": 1.0,
                ],
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
                parserOptions: [:],
                extensions: ["strings", "stringsdict"],
                template: .file(manifestDirectory.appending(component: "Template.stencil"))
            )
        )
        XCTAssertEqual(gotResourceName, "Strings")
    }

    func test_from_when_assets_plugin() throws {
        // Given
        let parserOptions: [String: ProjectDescription.ResourceSynthesizer.Parser.Option] = [
            "stringValue": "test",
            "intValue": 999,
            "boolValue": true,
            "doubleValue": 1.0,
        ]
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
            manifest: .assets(plugin: "Plugin", parserOptions: parserOptions),
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
                parserOptions: [
                    "stringValue": .init(value: "test"),
                    "intValue": .init(value: 999),
                    "boolValue": .init(value: true),
                    "doubleValue": .init(value: 1.0),
                ],
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

    func test_locate_when_a_resourceSynthesizer_and_git_directory_exists() throws {
        // Given
        let resourceSynthesizerDirectory = try temporaryPath()
        try createFolders(["this/is/a/very/nested/directory", "this/is/Tuist/ResourceSynthesizers", "this/.git"])

        // When
        let got = subject
            .locate(at: resourceSynthesizerDirectory.appending(try RelativePath(validating: "this/is/a/very/nested/directory")))

        // Then
        XCTAssertEqual(
            got,
            resourceSynthesizerDirectory.appending(try RelativePath(validating: "this/is/Tuist/ResourceSynthesizers"))
        )
    }

    func test_locate_when_a_resourceSynthesizer_directory_exists() throws {
        // Given
        let resourceSynthesizerDirectory = try temporaryPath()
        try createFolders(["this/is/a/very/nested/directory", "this/is/Tuist/ResourceSynthesizers"])

        // When
        let got = subject
            .locate(at: resourceSynthesizerDirectory.appending(try RelativePath(validating: "this/is/a/very/nested/directory")))

        // Then
        XCTAssertEqual(
            got,
            resourceSynthesizerDirectory.appending(try RelativePath(validating: "this/is/Tuist/ResourceSynthesizers"))
        )
    }

    func test_locate_when_a_git_directory_exists() throws {
        // Given
        let resourceSynthesizerDirectory = try temporaryPath()
        try createFolders(["this/is/a/very/nested/directory", "this/.git", "this/Tuist/ResourceSynthesizers"])

        // When
        let got = subject
            .locate(at: resourceSynthesizerDirectory.appending(try RelativePath(validating: "this/is/a/very/nested/directory")))

        // Then
        XCTAssertEqual(
            got,
            resourceSynthesizerDirectory.appending(try RelativePath(validating: "this/Tuist/ResourceSynthesizers"))
        )
    }

    func test_locate_when_multiple_tuist_directories_exists() throws {
        // Given
        let resourceSynthesizerDirectory = try temporaryPath()
        try createFolders(["this/is/a/very/nested/Tuist/ResourceSynthesizers", "this/is/Tuist/ResourceSynthesizers"])
        let paths = [
            "this/is/a/very/directory",
            "this/is/a/very/nested/directory",
        ]

        // When
        let got = try paths.map {
            subject.locate(at: resourceSynthesizerDirectory.appending(try RelativePath(validating: $0)))
        }

        // Then
        XCTAssertEqual(got, try [
            "this/is/Tuist/ResourceSynthesizers",
            "this/is/a/very/nested/Tuist/ResourceSynthesizers",
        ].map { resourceSynthesizerDirectory.appending(try RelativePath(validating: $0)) })
    }
}
