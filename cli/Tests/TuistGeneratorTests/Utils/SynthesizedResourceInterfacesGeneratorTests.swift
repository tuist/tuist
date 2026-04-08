import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import XcodeGraph

@testable import TuistGenerator

struct SynthesizedResourceInterfacesGeneratorTests {
    // swiftlint:disable line_length
    private static let expectedHeader = """
        // swiftlint:disable:this file_name
        // swiftlint:disable all
        // swift-format-ignore-file
        // swiftformat:disable all
        // Generated using tuist — https://github.com/tuist/tuist

        import Foundation

        // swiftlint:disable superfluous_disable_command
        // swiftlint:disable file_length

        // MARK: - Plist Files

        // swiftlint:disable identifier_name line_length number_separator type_body_length
        """

    private static let expectedFooter = """
        // swiftlint:enable identifier_name line_length number_separator type_body_length
        // swiftformat:enable all
        // swiftlint:enable all
        """
    // swiftlint:enable line_length

    @Test(.inTemporaryDirectory)
    func render_plistWithDictionaryValues_includesNonisolatedUnsafe() async throws {
        let rendered = try renderPlist(
            named: "DictConfig",
            content: [
                "serverURL": "https://example.com",
                "settings": ["retries": 3, "timeout": 30],
            ] as [String: Any]
        )

        let expectedBody = """
            public enum DictConfig: Sendable {
                public static let serverURL: String = #"https://example.com"#
                public nonisolated(unsafe) static let settings: [String: Any] = ["retries": 3, "timeout": 30]
            }
            """
        #expect(rendered == Self.expectedHeader + "\n" + expectedBody + "\n" + Self.expectedFooter + "\n")
    }

    @Test(.inTemporaryDirectory)
    func render_plistWithOnlyScalarValues_doesNotIncludeNonisolatedUnsafe() async throws {
        let rendered = try renderPlist(
            named: "ScalarConfig",
            content: [
                "appName": "MyApp",
                "version": 42,
                "debugEnabled": true,
            ] as [String: Any]
        )

        let expectedBody = """
            public enum ScalarConfig: Sendable {
                public static let appName: String = #"MyApp"#
                public static let debugEnabled: Bool = true
                public static let version: Int = 42
            }
            """
        #expect(rendered == Self.expectedHeader + "\n" + expectedBody + "\n" + Self.expectedFooter + "\n")
    }

    @Test(.inTemporaryDirectory)
    func render_plistWithArrayOfDictionaries_includesNonisolatedUnsafe() async throws {
        let rendered = try renderPlist(
            named: "ArrayConfig",
            content: [
                "endpoints": [
                    ["url": "https://a.com"],
                    ["url": "https://b.com"],
                ],
            ] as [String: Any]
        )

        // swiftlint:disable:next line_length
        let expectedBody = """
            public enum ArrayConfig: Sendable {
                public nonisolated(unsafe) static let endpoints: [[String: Any]] = [["url": #"https://a.com"#], ["url": #"https://b.com"#]]
            }
            """
        #expect(rendered == Self.expectedHeader + "\n" + expectedBody + "\n" + Self.expectedFooter + "\n")
    }

    private func renderPlist(named name: String, content: [String: Any]) throws -> String {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let plistPath = temporaryDirectory.appending(component: "\(name).plist")

        let plistData = try PropertyListSerialization.data(
            fromPropertyList: content,
            format: .xml,
            options: 0
        )
        try plistData.write(to: URL(fileURLWithPath: plistPath.pathString))

        return try SynthesizedResourceInterfacesGenerator().render(
            parser: .plists,
            parserOptions: [:],
            templateString: SynthesizedResourceInterfaceTemplates.plistsTemplate,
            name: "TestTarget",
            bundleName: nil,
            paths: [plistPath]
        )
    }
}
