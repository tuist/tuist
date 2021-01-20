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
    func test_dependencies() throws {
        // Given
        let manifest: ProjectDescription.Dependencies = Dependencies([
            .carthage(origin: .github(path: "Dependency1"), requirement: .exact("1.1.1"), platforms: [.iOS]),
            .carthage(origin: .git(path: "Dependency.git"), requirement: .branch("BranchName"), platforms: [.macOS]),
            .carthage(origin: .binary(path: "DependencyXYZ"), requirement: .atLeast("2.3.1"), platforms: [.tvOS]),
        ])

        // When
        let model = try TuistGraph.Dependencies.from(manifest: manifest)

        // Then
        XCTAssertEqual(model.carthageDependencies, [
            TuistGraph.CarthageDependency(origin: .github(path: "Dependency1"), requirement: .exact("1.1.1"), platforms: Set([.iOS])),
            TuistGraph.CarthageDependency(origin: .git(path: "Dependency.git"), requirement: .branch("BranchName"), platforms: Set([.macOS])),
            TuistGraph.CarthageDependency(origin: .binary(path: "DependencyXYZ"), requirement: .atLeast("2.3.1"), platforms: Set([.tvOS])),
        ])
    }
}
