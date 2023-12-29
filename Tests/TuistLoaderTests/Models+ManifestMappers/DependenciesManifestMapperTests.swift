import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class DependenciesManifestMapperTests: TuistUnitTestCase {
    func test_from() throws {
        // Given
        let temporaryPath = try temporaryPath()

        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        let manifest: ProjectDescription.Dependencies = Dependencies(
            swiftPackageManager: .init(),
            platforms: [.iOS, .macOS, .tvOS]
        )

        // When
        let got = try TuistGraph.Dependencies.from(manifest: manifest, generatorPaths: generatorPaths)

        // Then
        let expected: TuistGraph.Dependencies = .init(
            swiftPackageManager: .init(
                .manifest,
                productTypes: [:],
                baseSettings: .init(configurations: [
                    .debug: .init(settings: [:], xcconfig: nil),
                    .release: .init(settings: [:], xcconfig: nil),
                ]),
                targetSettings: [:]
            ),
            platforms: [.iOS, .macOS, .tvOS]
        )
        XCTAssertEqual(got, expected)
    }
}
