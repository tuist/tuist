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

struct SettingsManifestMapperTests {
    @Test(.inTemporaryDirectory) func test_from() throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: temporaryPath
        )
        let debug: ProjectDescription.Configuration = .debug(
            name: .debug,
            settings: ["Debug": .string("Debug")],
            xcconfig: "debug.xcconfig"
        )
        let release: ProjectDescription.Configuration = .release(
            name: .release,
            settings: ["Release": .string("Release")],
            xcconfig: "release.xcconfig"
        )
        let manifest: ProjectDescription.Settings = .settings(
            base: ["base": .string("base")],
            configurations: [
                debug,
                release,
            ]
        )

        // When
        let model = try XcodeGraph.Settings.from(manifest: manifest, generatorPaths: generatorPaths)

        // Then
        #expect(model.base.count == manifest.base.count)

        let sortedConfigurations = model.configurations.sorted { l, r -> Bool in l.key.name < r.key.name }
        let sortedManifestConfigurations = manifest.configurations.sorted(by: { $0.name.rawValue < $1.name.rawValue })
        for (configuration, manifestConfiguration) in zip(sortedConfigurations, sortedManifestConfigurations) {
            #expect(configuration.1?.settings.count == manifestConfiguration.settings.count)
            #expect(
                configuration.1?.xcconfig ==
                    (try manifestConfiguration.xcconfig.map { try generatorPaths.resolve(path: $0) })
            )
        }
    }
}
