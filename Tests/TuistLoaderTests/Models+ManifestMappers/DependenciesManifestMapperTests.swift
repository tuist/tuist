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
        let manifest: ProjectDescription.Dependencies = Dependencies(
            carthageDependencies: .init(
                dependencies: [
                    .github(path: "Dependency1", requirement: .exact("1.1.1")),
                    .git(path: "Dependency.git", requirement: .branch("BranchName")),
                    .binary(path: "DependencyXYZ", requirement: .atLeast("2.3.1")),
                ],
                options: .init(platforms: [.iOS, .macOS, .tvOS], useXCFrameworks: true)
            )
        )

        // When
        let model = try TuistGraph.Dependencies.from(manifest: manifest)

        // Then
        let expected: TuistGraph.Dependencies = .init(
            carthageDependencies: .init(
                dependencies: [
                    .github(path: "Dependency1", requirement: .exact("1.1.1")),
                    .git(path: "Dependency.git", requirement: .branch("BranchName")),
                    .binary(path: "DependencyXYZ", requirement: .atLeast("2.3.1")),
                ],
                options: .init(platforms: [.iOS, .macOS, .tvOS], useXCFrameworks: true)
            )
        )
        XCTAssertEqual(model, expected)
    }
}
