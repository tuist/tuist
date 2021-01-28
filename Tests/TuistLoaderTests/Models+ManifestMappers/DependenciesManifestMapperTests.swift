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
        let temporaryPath = try self.temporaryPath()
        let localPackagePath = temporaryPath.appending(component: "LocalPackage")
        
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        let manifest: ProjectDescription.Dependencies = Dependencies([
            .carthage(origin: .github(path: "Dependency1"), requirement: .exact("1.1.1"), platforms: [.iOS]),
            .carthage(origin: .git(path: "Dependency.git"), requirement: .branch("BranchName"), platforms: [.macOS]),
            .carthage(origin: .binary(path: "DependencyXYZ"), requirement: .atLeast("2.3.1"), platforms: [.tvOS]),
            .swiftPackageManager(package: .local(path: .init(localPackagePath.pathString))),
            .swiftPackageManager(package: .remote(url: "RemotePackage.com", requirement: .exact("1.2.3"))),
        ])

        // When
        let got = try TuistGraph.Dependencies.from(manifest: manifest, generatorPaths: generatorPaths)

        // Then
        let expected = TuistGraph.Dependencies(
            carthageDependencies: [
                TuistGraph.CarthageDependency(origin: .github(path: "Dependency1"), requirement: .exact("1.1.1"), platforms: Set([.iOS])),
                TuistGraph.CarthageDependency(origin: .git(path: "Dependency.git"), requirement: .branch("BranchName"), platforms: Set([.macOS])),
                TuistGraph.CarthageDependency(origin: .binary(path: "DependencyXYZ"), requirement: .atLeast("2.3.1"), platforms: Set([.tvOS])),
            ],
            swiftPackageManagerDependencies: [
                TuistGraph.SwiftPackageManagerDependency(package: .local(path: localPackagePath)),
                TuistGraph.SwiftPackageManagerDependency(package: .remote(url: "RemotePackage.com", requirement: .exact("1.2.3")))
            ]
        )
        XCTAssertEqual(got, expected)
    }
}
