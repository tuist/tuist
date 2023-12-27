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
    func test_from_when_external_xcframework() throws {
        // Given
        let dependency = ProjectDescription.TargetDependency.external(name: "library")
        let generatorPaths = GeneratorPaths(manifestDirectory: try AbsolutePath(validating: "/"))

        // When
        let got = try TuistGraph.TargetDependency.from(
            manifest: dependency,
            generatorPaths: generatorPaths,
            externalDependencies: ["library": [.xcframework(path: "/path.xcframework", status: .required)]]
        )

        // Then
        XCTAssertEqual(got.count, 1)
        guard case let .xcframework(path, status, _) = got[0] else {
            XCTFail("Dependency should be xcframework")
            return
        }
        XCTAssertEqual(path, "/path.xcframework")
        XCTAssertEqual(status, .required)
    }

    func test_from_when_external_project() throws {
        // Given
        let dependency = ProjectDescription.TargetDependency.external(name: "library")
        let generatorPaths = GeneratorPaths(manifestDirectory: try AbsolutePath(validating: "/"))

        // When
        let got = try TuistGraph.TargetDependency.from(
            manifest: dependency,
            generatorPaths: generatorPaths,
            externalDependencies: ["library": [.project(target: "Target", path: "/Project")]]
        )

        // Then
        XCTAssertEqual(got.count, 1)
        guard case let .project(target, path, _) = got[0] else {
            XCTFail("Dependency should be project")
            return
        }
        XCTAssertEqual(target, "Target")
        XCTAssertEqual(path, "/Project")
    }

    func test_from_when_external_multiple() throws {
        // Given
        let dependency = ProjectDescription.TargetDependency.external(name: "library")
        let generatorPaths = GeneratorPaths(manifestDirectory: try AbsolutePath(validating: "/"))

        // When
        let got = try TuistGraph.TargetDependency.from(
            manifest: dependency,
            generatorPaths: generatorPaths,
            externalDependencies: [
                "library": [
                    .xcframework(path: "/path.xcframework", status: .required),
                    .project(target: "Target", path: "/Project"),
                ],
            ]
        )

        // Then
        XCTAssertEqual(got.count, 2)
        guard case let .xcframework(frameworkPath, status, _) = got[0] else {
            XCTFail("First dependency should be xcframework")
            return
        }
        XCTAssertEqual(frameworkPath, "/path.xcframework")
        XCTAssertEqual(status, .required)

        guard case let .project(target, path, _) = got[1] else {
            XCTFail("Dependency should be project")
            return
        }
        XCTAssertEqual(target, "Target")
        XCTAssertEqual(path, "/Project")
    }

    func test_from_when_package_runtime() throws {
        // Given
        let dependency = ProjectDescription.TargetDependency.package(product: "RuntimePackageProduct", type: .runtime)
        let generatorPaths = GeneratorPaths(manifestDirectory: try AbsolutePath(validating: "/"))

        // When
        let got = try TuistGraph.TargetDependency.from(
            manifest: dependency,
            generatorPaths: generatorPaths,
            externalDependencies: [:]
        )

        // Then
        XCTAssertEqual(got.count, 1)
        guard case let .package(product, type, _) = got[0] else {
            XCTFail("Dependency should be package")
            return
        }
        XCTAssertEqual(product, "RuntimePackageProduct")
        XCTAssertEqual(type, .runtime)
    }

    func test_from_when_package_macro() throws {
        // Given
        let dependency = ProjectDescription.TargetDependency.package(product: "MacroPackageProduct", type: .macro)
        let generatorPaths = GeneratorPaths(manifestDirectory: try AbsolutePath(validating: "/"))

        // When
        let got = try TuistGraph.TargetDependency.from(
            manifest: dependency,
            generatorPaths: generatorPaths,
            externalDependencies: [:]
        )

        // Then
        XCTAssertEqual(got.count, 1)
        guard case let .package(product, type, _) = got[0] else {
            XCTFail("Dependency should be package")
            return
        }
        XCTAssertEqual(product, "MacroPackageProduct")
        XCTAssertEqual(type, .macro)
    }

    func test_from_when_package_plugin() throws {
        // Given
        let dependency = ProjectDescription.TargetDependency.package(product: "PluginPackageProduct", type: .plugin)
        let generatorPaths = GeneratorPaths(manifestDirectory: try AbsolutePath(validating: "/"))

        // When
        let got = try TuistGraph.TargetDependency.from(
            manifest: dependency,
            generatorPaths: generatorPaths,
            externalDependencies: [:]
        )

        // Then
        XCTAssertEqual(got.count, 1)
        guard case let .package(product, type, _) = got[0] else {
            XCTFail("Dependency should be package")
            return
        }
        XCTAssertEqual(product, "PluginPackageProduct")
        XCTAssertEqual(type, .plugin)
    }

    func test_from_when_sdkLibrary() throws {
        // Given
        let dependency = ProjectDescription.TargetDependency.sdk(name: "c++", type: .library, status: .required)
        let generatorPaths = GeneratorPaths(manifestDirectory: try AbsolutePath(validating: "/"))

        // When
        let got = try TuistGraph.TargetDependency.from(
            manifest: dependency,
            generatorPaths: generatorPaths,
            externalDependencies: [:]
        )

        // Then
        XCTAssertEqual(got.count, 1)
        guard case let .sdk(name, status, _) = got[0] else {
            XCTFail("Dependency should be sdk")
            return
        }
        XCTAssertEqual(name, "libc++.tbd")
        XCTAssertEqual(status, .required)
    }

    func test_from_when_sdkFramework() throws {
        // Given
        let dependency = ProjectDescription.TargetDependency.sdk(name: "ARKit", type: .framework, status: .required)
        let generatorPaths = GeneratorPaths(manifestDirectory: try AbsolutePath(validating: "/"))

        // When
        let got = try TuistGraph.TargetDependency.from(
            manifest: dependency,
            generatorPaths: generatorPaths,
            externalDependencies: [:]
        )

        // Then
        XCTAssertEqual(got.count, 1)
        guard case let .sdk(name, status, _) = got[0] else {
            XCTFail("Dependency should be sdk")
            return
        }
        XCTAssertEqual(name, "ARKit.framework")
        XCTAssertEqual(status, .required)
    }
}
