import FileSystem
import FileSystemTesting
import Foundation
import ProjectDescription
import Testing
import TuistCore
import TuistSupport
import XcodeGraph

@testable import TuistLoader
@testable import TuistTesting

struct ConfigurationManifestMapperTests {
    @Test(.inTemporaryDirectory) func from_returns_nil_when_manifest_is_nil() throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: temporaryPath
        )

        // When
        let got = try XcodeGraph.Configuration.from(manifest: nil, generatorPaths: generatorPaths)

        // Then
        #expect(got == nil)
    }

    @Test(.inTemporaryDirectory) func from_returns_the_correct_value_when_manifest_is_not_nil() throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let xcconfigPath = temporaryPath.appending(component: "Config.xcconfig")
        let settings: [String: ProjectDescription.SettingValue] = ["A": "B"]
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: temporaryPath
        )
        let manifest: ProjectDescription.Configuration = .debug(
            name: .debug,
            settings: settings,
            xcconfig: .path(xcconfigPath.pathString)
        )

        // When
        let got = try XcodeGraph.Configuration.from(
            manifest: manifest,
            generatorPaths: generatorPaths
        )

        // Then
        let aSetting = try #require(got?.settings["A"])

        guard case let XcodeGraph.SettingValue.string(aString) = aSetting else {
            Issue.record("Expected A to be a string")
            return
        }
        #expect(aString == "B")
        #expect(got?.xcconfig?.pathString == xcconfigPath.pathString)
    }
}
