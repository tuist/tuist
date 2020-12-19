import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class DependenciesManifestMapperTests: TuistUnitTestCase {
    func test_dependencies() throws {
        // Given
        let manifest: ProjectDescription.Dependencies = Dependencies([
            .carthage(name: "Dependency1", requirement: .exact("1.1.1"), platforms: [.iOS]),
            .carthage(name: "Dependency2", requirement: .branch("BranchName"), platforms: [.macOS]),
        ])

        // When
        let model = try TuistCore.Dependencies.from(manifest: manifest)

        // Then
        XCTAssertEqual(model.carthageDependencies, [
            TuistCore.CarthageDependency(name: "Dependency1", requirement: .exact("1.1.1"), platforms: Set([.iOS])),
            TuistCore.CarthageDependency(name: "Dependency2", requirement: .branch("BranchName"), platforms: Set([.macOS])),
        ])
    }
}
