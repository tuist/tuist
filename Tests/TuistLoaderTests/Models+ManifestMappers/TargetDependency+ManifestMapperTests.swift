import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class DependencyManifestMapperTests: TuistUnitTestCase {
    func test_from_when_localPackage() throws {
        // Given
        let dependency = ProjectDescription.TargetDependency.package(product: "library")
        let generatorPaths = GeneratorPaths(manifestDirectory: AbsolutePath("/"))

        // When
        let got = try TuistGraph.TargetDependency.from(manifest: dependency, generatorPaths: generatorPaths, externalDependencies: [:])

        // Then
        XCTAssertEqual(got.count, 1)
        guard case let .package(product) = got[0] else {
            XCTFail("Dependency should be package")
            return
        }
        XCTAssertEqual(product, "library")
    }

    func test_from_when_external_xcframework() throws {
        // Given
        let dependency = ProjectDescription.TargetDependency.external(name: "library")
        let generatorPaths = GeneratorPaths(manifestDirectory: AbsolutePath("/"))

        // When
        let got = try TuistGraph.TargetDependency.from(
            manifest: dependency,
            generatorPaths: generatorPaths,
            externalDependencies: [
                "library": [.xcframework(path: "/path.xcframework")],
            ]
        )

        // Then
        XCTAssertEqual(got.count, 1)
        guard case let .xcframework(path) = got[0] else {
            XCTFail("Dependency should be xcframework")
            return
        }
        XCTAssertEqual(path, "/path.xcframework")
    }

    func test_from_when_external_project() throws {
        // Given
        let dependency = ProjectDescription.TargetDependency.external(name: "library")
        let generatorPaths = GeneratorPaths(manifestDirectory: AbsolutePath("/"))

        // When
        let got = try TuistGraph.TargetDependency.from(
            manifest: dependency,
            generatorPaths: generatorPaths,
            externalDependencies: [
                "library": [.project(target: "Target", path: "/Project")],
            ]
        )

        // Then
        XCTAssertEqual(got.count, 1)
        guard case let .project(target, path) = got[0] else {
            XCTFail("Dependency should be project")
            return
        }
        XCTAssertEqual(target, "Target")
        XCTAssertEqual(path, "/Project")
    }

    func test_from_when_external_multiple() throws {
        // Given
        let dependency = ProjectDescription.TargetDependency.external(name: "library")
        let generatorPaths = GeneratorPaths(manifestDirectory: AbsolutePath("/"))

        // When
        let got = try TuistGraph.TargetDependency.from(
            manifest: dependency,
            generatorPaths: generatorPaths,
            externalDependencies: [
                "library": [
                    .xcframework(path: "/path.xcframework"),
                    .project(target: "Target", path: "/Project"),
                ],
            ]
        )

        // Then
        XCTAssertEqual(got.count, 2)
        guard case let .xcframework(frameworkPath) = got[0] else {
            XCTFail("First dependency should be xcframework")
            return
        }
        XCTAssertEqual(frameworkPath, "/path.xcframework")

        guard case let .project(target, path) = got[1] else {
            XCTFail("Dependency should be project")
            return
        }
        XCTAssertEqual(target, "Target")
        XCTAssertEqual(path, "/Project")
    }
}
