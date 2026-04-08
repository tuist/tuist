import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import XcodeGraph

@testable import TuistGenerator

struct SynthesizedResourceInterfacesGeneratorTests {
    private let subject = SynthesizedResourceInterfacesGenerator()

    @Test(.inTemporaryDirectory)
    func render_plistWithDictionaryValues_includesNonisolatedUnsafe() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let plistPath = temporaryDirectory.appending(component: "Config.plist")

        let plistData = try PropertyListSerialization.data(
            fromPropertyList: [
                "serverURL": "https://example.com",
                "settings": ["timeout": 30, "retries": 3],
            ] as [String: Any],
            format: .xml,
            options: 0
        )
        try plistData.write(to: URL(fileURLWithPath: plistPath.pathString))

        let rendered = try subject.render(
            parser: .plists,
            parserOptions: [:],
            templateString: SynthesizedResourceInterfaceTemplates.plistsTemplate,
            name: "TestTarget",
            bundleName: nil,
            paths: [plistPath]
        )

        #expect(rendered.contains("nonisolated(unsafe) static let settings"))
        #expect(!rendered.contains("nonisolated(unsafe) static let serverUrl"))
    }

    @Test(.inTemporaryDirectory)
    func render_plistWithOnlyScalarValues_doesNotIncludeNonisolatedUnsafe() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let plistPath = temporaryDirectory.appending(component: "Config.plist")

        let plistData = try PropertyListSerialization.data(
            fromPropertyList: [
                "appName": "MyApp",
                "version": 42,
                "debugEnabled": true,
            ] as [String: Any],
            format: .xml,
            options: 0
        )
        try plistData.write(to: URL(fileURLWithPath: plistPath.pathString))

        let rendered = try subject.render(
            parser: .plists,
            parserOptions: [:],
            templateString: SynthesizedResourceInterfaceTemplates.plistsTemplate,
            name: "TestTarget",
            bundleName: nil,
            paths: [plistPath]
        )

        #expect(!rendered.contains("nonisolated(unsafe)"))
    }

    @Test(.inTemporaryDirectory)
    func render_plistWithArrayOfDictionaries_includesNonisolatedUnsafe() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let plistPath = temporaryDirectory.appending(component: "Config.plist")

        let plistData = try PropertyListSerialization.data(
            fromPropertyList: [
                "endpoints": [
                    ["url": "https://a.com"],
                    ["url": "https://b.com"],
                ],
            ] as [String: Any],
            format: .xml,
            options: 0
        )
        try plistData.write(to: URL(fileURLWithPath: plistPath.pathString))

        let rendered = try subject.render(
            parser: .plists,
            parserOptions: [:],
            templateString: SynthesizedResourceInterfaceTemplates.plistsTemplate,
            name: "TestTarget",
            bundleName: nil,
            paths: [plistPath]
        )

        #expect(rendered.contains("nonisolated(unsafe) static let endpoints"))
    }
}
