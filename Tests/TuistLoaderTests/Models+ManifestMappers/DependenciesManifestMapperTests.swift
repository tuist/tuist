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
            carthage: [
                .github(path: "Dependency1", requirement: .exact("1.1.1")),
                .git(path: "Dependency.git", requirement: .branch("BranchName")),
                .binary(path: "DependencyXYZ", requirement: .atLeast("2.3.1")),
            ],
            swiftPackageManager: .init(),
            platforms: [.iOS, .macOS, .tvOS]
        )

        // When
        let got = try TuistGraph.Dependencies.from(manifest: manifest, generatorPaths: generatorPaths)

        // Then
        let expected: TuistGraph.Dependencies = .init(
            carthage: .init(
                [
                    .github(path: "Dependency1", requirement: .exact("1.1.1")),
                    .git(path: "Dependency.git", requirement: .branch("BranchName")),
                    .binary(path: "DependencyXYZ", requirement: .atLeast("2.3.1")),
                ]
            ),
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
