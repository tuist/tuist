import FileSystem
import FileSystemTesting
import Foundation
import Path
import ProjectDescription
import Testing
import TuistCore
import TuistRootDirectoryLocator
import TuistTesting
import XcodeGraph

@testable import TuistLoader

struct ResourceSynthesizerManifestMapperTests {
    private let resourceSynthesizerPathLocator: MockResourceSynthesizerPathLocator
    let subject: ResourceSynthesizerPathLocator

    init() {
        resourceSynthesizerPathLocator = MockResourceSynthesizerPathLocator()
        subject = ResourceSynthesizerPathLocator(rootDirectoryLocator: RootDirectoryLocator())
    }

    @Test(.inTemporaryDirectory) func from_when_default_strings() async throws {
        // Given
        let manifestDirectory = try #require(FileSystem.temporaryTestDirectory)
        let rootDirectory = manifestDirectory

        // When
        let got = try await ResourceSynthesizer.from(
            manifest: .strings(),
            generatorPaths: GeneratorPaths(manifestDirectory: manifestDirectory, rootDirectory: rootDirectory),
            plugins: .none,
            resourceSynthesizerPathLocator: resourceSynthesizerPathLocator
        )

        // Then
        #expect(got == .init(
            parser: .strings, parserOptions: [:],
            extensions: ["strings", "stringsdict"], template: .defaultTemplate("Strings")
        ))
    }

    @Test(.inTemporaryDirectory) func from_when_default_strings_with_parserOptions() async throws {
        // Given
        let parserOptions: [String: ProjectDescription.ResourceSynthesizer.Parser.Option] = [
            "stringValue": "test", "intValue": 999, "boolValue": true, "doubleValue": 1.0,
        ]
        let manifestDirectory = try #require(FileSystem.temporaryTestDirectory)
        let rootDirectory = manifestDirectory

        // When
        let got = try await ResourceSynthesizer.from(
            manifest: .strings(parserOptions: parserOptions),
            generatorPaths: GeneratorPaths(manifestDirectory: manifestDirectory, rootDirectory: rootDirectory),
            plugins: .none,
            resourceSynthesizerPathLocator: resourceSynthesizerPathLocator
        )

        // Then
        #expect(got == .init(
            parser: .strings,
            parserOptions: ["stringValue": "test", "intValue": 999, "boolValue": true, "doubleValue": 1.0],
            extensions: ["strings", "stringsdict"], template: .defaultTemplate("Strings")
        ))
    }

    @Test(.inTemporaryDirectory) func from_when_default_strings_and_custom_template_defined() async throws {
        // Given
        let manifestDirectory = try #require(FileSystem.temporaryTestDirectory)
        let rootDirectory = manifestDirectory
        var gotResourceName: String?
        resourceSynthesizerPathLocator.templatePathResourceStub = { resourceName, path in
            gotResourceName = resourceName
            return path.appending(component: "Template.stencil")
        }

        // When
        let got = try await ResourceSynthesizer.from(
            manifest: .strings(),
            generatorPaths: GeneratorPaths(manifestDirectory: manifestDirectory, rootDirectory: rootDirectory),
            plugins: .none,
            resourceSynthesizerPathLocator: resourceSynthesizerPathLocator
        )

        // Then
        #expect(got == .init(
            parser: .strings, parserOptions: [:],
            extensions: ["strings", "stringsdict"],
            template: .file(manifestDirectory.appending(component: "Template.stencil"))
        ))
        #expect(gotResourceName == "Strings")
    }

    @Test(.inTemporaryDirectory) func from_when_assets_plugin() async throws {
        // Given
        let parserOptions: [String: ProjectDescription.ResourceSynthesizer.Parser.Option] = [
            "stringValue": "test", "intValue": 999, "boolValue": true, "doubleValue": 1.0,
        ]
        let manifestDirectory = try #require(FileSystem.temporaryTestDirectory)
        let rootDirectory = manifestDirectory
        var invokedPluginNames: [String] = []
        var invokedResourceNames: [String] = []
        var invokedResourceSynthesizerPlugins: [TuistCore.PluginResourceSynthesizer] = []
        resourceSynthesizerPathLocator.templatePathStub = { pluginName, resourceName, resourceSynthesizerPlugins in
            invokedPluginNames.append(pluginName)
            invokedResourceNames.append(resourceName)
            invokedResourceSynthesizerPlugins.append(contentsOf: resourceSynthesizerPlugins)
            return manifestDirectory.appending(component: "PluginTemplate.stencil")
        }

        // When
        let got = try await ResourceSynthesizer.from(
            manifest: .assets(plugin: "Plugin", parserOptions: parserOptions),
            generatorPaths: GeneratorPaths(manifestDirectory: manifestDirectory, rootDirectory: rootDirectory),
            plugins: .test(resourceSynthesizers: [.test(name: "Plugin")]),
            resourceSynthesizerPathLocator: resourceSynthesizerPathLocator
        )

        // Then
        #expect(got == .init(
            parser: .assets,
            parserOptions: [
                "stringValue": .init(value: "test"), "intValue": .init(value: 999),
                "boolValue": .init(value: true), "doubleValue": .init(value: 1.0),
            ],
            extensions: ["xcassets"],
            template: .file(manifestDirectory.appending(component: "PluginTemplate.stencil"))
        ))
        #expect(invokedPluginNames == ["Plugin"])
        #expect(invokedResourceNames == ["Assets"])
        #expect(invokedResourceSynthesizerPlugins == [.test(name: "Plugin")])
    }

    @Test(.inTemporaryDirectory) func locate_when_a_resourceSynthesizer_and_git_directory_exists() async throws {
        let resourceSynthesizerDirectory = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.makeDirectories([
            "this/is/a/very/nested/directory",
            "this/is/Tuist/ResourceSynthesizers",
            "this/.git",
        ])

        let got = try await subject
            .locate(at: resourceSynthesizerDirectory.appending(try RelativePath(validating: "this/is/a/very/nested/directory")))

        #expect(got == resourceSynthesizerDirectory.appending(try RelativePath(validating: "this/is/Tuist/ResourceSynthesizers")))
    }

    @Test(.inTemporaryDirectory) func locate_when_a_resourceSynthesizer_directory_exists() async throws {
        let resourceSynthesizerDirectory = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.makeDirectories(["this/is/a/very/nested/directory", "this/is/Tuist/ResourceSynthesizers"])

        let got = try await subject
            .locate(at: resourceSynthesizerDirectory.appending(try RelativePath(validating: "this/is/a/very/nested/directory")))

        #expect(got == resourceSynthesizerDirectory.appending(try RelativePath(validating: "this/is/Tuist/ResourceSynthesizers")))
    }

    @Test(.inTemporaryDirectory) func locate_when_a_git_directory_exists() async throws {
        let resourceSynthesizerDirectory = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.makeDirectories(["this/is/a/very/nested/directory", "this/.git", "this/Tuist/ResourceSynthesizers"])

        let got = try await subject
            .locate(at: resourceSynthesizerDirectory.appending(try RelativePath(validating: "this/is/a/very/nested/directory")))

        #expect(got == resourceSynthesizerDirectory.appending(try RelativePath(validating: "this/Tuist/ResourceSynthesizers")))
    }

    @Test(.inTemporaryDirectory) func locate_when_multiple_tuist_directories_exists() async throws {
        let resourceSynthesizerDirectory = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.makeDirectories([
            "this/is/a/very/nested/Tuist/ResourceSynthesizers",
            "this/is/Tuist/ResourceSynthesizers",
        ])
        let paths = ["this/is/a/very/directory", "this/is/a/very/nested/directory"]

        let got = try await paths.concurrentMap {
            try await subject.locate(at: resourceSynthesizerDirectory.appending(try RelativePath(validating: $0)))
        }

        #expect(got == (try [
            "this/is/Tuist/ResourceSynthesizers", "this/is/a/very/nested/Tuist/ResourceSynthesizers",
        ].map { resourceSynthesizerDirectory.appending(try RelativePath(validating: $0)) }))
    }
}
