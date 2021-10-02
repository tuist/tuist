import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class CodeCoverageManifestMapperTests: TuistUnitTestCase {
    private typealias Manifest = ProjectDescription.Config.GenerationOptions.CodeCoverageMode

    func test_from_returnsTheCorrectValue_whenManifestIsAll() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        let manifest = Manifest.all

        // When
        let got = try TuistGraph.CodeCoverageMode.from(manifest: manifest, generatorPaths: generatorPaths)

        // Then
        XCTAssertEqual(.all, got)
    }

    func test_from_returnsTheCorrectValue_whenManifestIsRelevant() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        let manifest = Manifest.relevant

        // When
        let got = try TuistGraph.CodeCoverageMode.from(manifest: manifest, generatorPaths: generatorPaths)

        // Then
        XCTAssertEqual(.relevant, got)
    }

    func test_from_returnsTheCorrectValue_whenManifestIsTargets() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        let targetRef = ProjectDescription.TargetReference(projectPath: nil, target: "Target")
        let manifest = Manifest.targets([targetRef])

        // When
        let got = try TuistGraph.CodeCoverageMode.from(manifest: manifest, generatorPaths: generatorPaths)

        // Then
        XCTAssertEqual(
            got,
            .targets([
                TargetReference(
                    projectPath: try generatorPaths.resolveSchemeActionProjectPath(nil),
                    name: "Target"
                ),
            ])
        )
    }
}
