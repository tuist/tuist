import Foundation
import Path
import ProjectDescription
import TuistCore
import TuistSupport
import XcodeGraph
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class SettingsManifestMapperTests: TuistUnitTestCase {
    func test_from() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
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
        XCTAssertSettingsMatchesManifest(settings: model, matches: manifest, at: temporaryPath, generatorPaths: generatorPaths)
    }
}
