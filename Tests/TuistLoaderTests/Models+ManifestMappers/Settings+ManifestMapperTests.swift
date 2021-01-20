import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport
import XCTest
import TuistGraph

@testable import TuistLoader
@testable import TuistSupportTesting

final class SettingsManifestMapperTests: TuistUnitTestCase {
    func test_from() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        let debug = ProjectDescription.Configuration(settings: ["Debug": .string("Debug")], xcconfig: "debug.xcconfig")
        let release = ProjectDescription.Configuration(settings: ["Release": .string("Release")], xcconfig: "release.xcconfig")
        let manifest = ProjectDescription.Settings(base: ["base": .string("base")], debug: debug, release: release)

        // When
        let model = try TuistGraph.Settings.from(manifest: manifest, generatorPaths: generatorPaths)

        // Then
        XCTAssertSettingsMatchesManifest(settings: model, matches: manifest, at: temporaryPath, generatorPaths: generatorPaths)
    }
}
