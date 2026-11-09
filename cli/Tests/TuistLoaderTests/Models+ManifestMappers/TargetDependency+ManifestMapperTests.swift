import Foundation
import Path
import ProjectDescription
import TestCoverageAttribution
import Testing
import TuistCore
import TuistSupport
import XcodeGraph
import XCTest

@testable import TuistLoader
@testable import TuistTesting

final class DependencyManifestMapperTests: TuistUnitTestCase {
    func test_from_when_external_xcframework() throws {
        // Given
        let dependency = ProjectDescription.TargetDependency.external(name: "library")

        let generatorPaths = GeneratorPaths(manifestDirectory: try AbsolutePath(validating: "/"), rootDirectory: "/")

        // When
        let got = try XcodeGraph.TargetDependency.from(
            manifest: dependency,
            generatorPaths: generatorPaths,
            externalDependencies: ["library": [.xcframework(
                path: "/path.xcframework",
                expectedSignature: nil,
                status: .required
            )]]
        )

        // Then
        XCTAssertEqual(got.count, 1)
        guard case let .xcframework(path, _, status, _) = got[0] else {
            XCTFail("Dependency should be xcframework")
            return
        }
        XCTAssertEqual(path, "/path.xcframework")
        XCTAssertEqual(status, .required)
    }

    func test_from_when_external_project() throws {
        // Given
        let dependency = ProjectDescription.TargetDependency.external(name: "library")
        let generatorPaths = GeneratorPaths(manifestDirectory: try AbsolutePath(validating: "/"), rootDirectory: "/")

        // When
        let got = try XcodeGraph.TargetDependency.from(
            manifest: dependency,
            generatorPaths: generatorPaths,
            externalDependencies: ["library": [.project(target: "Target", path: "/Project")]]
        )

        // Then
        XCTAssertEqual(got.count, 1)
        guard case let .project(target, path, _, _) = got[0] else {
            XCTFail("Dependency should be project")
            return
        }
        XCTAssertEqual(target, "Target")
        XCTAssertEqual(path, "/Project")
    }

    func test_from_when_external_multiple() throws {
        // Given
        let dependency = ProjectDescription.TargetDependency.external(name: "library")
        let generatorPaths = GeneratorPaths(manifestDirectory: try AbsolutePath(validating: "/"), rootDirectory: "/")

        // When
        let got = try XcodeGraph.TargetDependency.from(
            manifest: dependency,
            generatorPaths: generatorPaths,
            externalDependencies: [
                "library": [
                    .xcframework(path: "/path.xcframework", expectedSignature: nil, status: .required),
                    .project(target: "Target", path: "/Project"),
                ],
            ]
        )

        // Then
        XCTAssertEqual(got.count, 2)
        guard case let .xcframework(frameworkPath, _, status, _) = got[0] else {
            XCTFail("First dependency should be xcframework")
            return
        }
        XCTAssertEqual(frameworkPath, "/path.xcframework")
        XCTAssertEqual(status, .required)

        guard case let .project(target, path, _, _) = got[1] else {
            XCTFail("Dependency should be project")
            return
        }
        XCTAssertEqual(target, "Target")
        XCTAssertEqual(path, "/Project")
    }

    func test_from_when_package_runtime() throws {
        // Given
        let dependency = ProjectDescription.TargetDependency.package(product: "RuntimePackageProduct", type: .runtime)
        let generatorPaths = GeneratorPaths(manifestDirectory: try AbsolutePath(validating: "/"), rootDirectory: "/")

        // When
        let got = try XcodeGraph.TargetDependency.from(
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

    func test_from_when_package_runtimeEmbedded() throws {
        // Given
        let dependency = ProjectDescription.TargetDependency.package(
            product: "RuntimeEmbeddedPackageProduct",
            type: .runtimeEmbedded
        )
        let generatorPaths = GeneratorPaths(manifestDirectory: try AbsolutePath(validating: "/"), rootDirectory: "/")

        // When
        let got = try XcodeGraph.TargetDependency.from(
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
        XCTAssertEqual(product, "RuntimeEmbeddedPackageProduct")
        XCTAssertEqual(type, .runtimeEmbedded)
    }

    func test_from_when_package_macro() throws {
        // Given
        let dependency = ProjectDescription.TargetDependency.package(product: "MacroPackageProduct", type: .macro)
        let generatorPaths = GeneratorPaths(manifestDirectory: try AbsolutePath(validating: "/"), rootDirectory: "/")

        // When
        let got = try XcodeGraph.TargetDependency.from(
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
        let generatorPaths = GeneratorPaths(manifestDirectory: try AbsolutePath(validating: "/"), rootDirectory: "/")

        // When
        let got = try XcodeGraph.TargetDependency.from(
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

    func test_from_when_macro() throws {
        // Given
        let dependency = ProjectDescription.TargetDependency.macro(name: "MacroProduct")
        let generatorPaths = GeneratorPaths(manifestDirectory: try AbsolutePath(validating: "/"), rootDirectory: "/")

        // When
        let got = try XcodeGraph.TargetDependency.from(
            manifest: dependency,
            generatorPaths: generatorPaths,
            externalDependencies: [:]
        )

        // Then
        XCTAssertEqual(got.count, 1)
        guard case let .target(name, linkerStatus, _) = got[0] else {
            XCTFail("Dependency should be package")
            return
        }
        XCTAssertEqual(name, "MacroProduct")
        XCTAssertEqual(linkerStatus, .required)
    }

    func test_from_when_sdkLibrary() throws {
        // Given
        let dependency = ProjectDescription.TargetDependency.sdk(name: "c++", type: .library, status: .required)
        let generatorPaths = GeneratorPaths(manifestDirectory: try AbsolutePath(validating: "/"), rootDirectory: "/")

        // When
        let got = try XcodeGraph.TargetDependency.from(
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

    func test_from_when_sdkSwiftLibrary() throws {
        // Given
        let dependency = ProjectDescription.TargetDependency.sdk(name: "Observation", type: .swiftLibrary, status: .required)
        let generatorPaths = GeneratorPaths(manifestDirectory: try AbsolutePath(validating: "/"), rootDirectory: "/")

        // When
        let got = try XcodeGraph.TargetDependency.from(
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
        XCTAssertEqual(name, "libswiftObservation.tbd")
        XCTAssertEqual(status, .required)
    }

    func test_from_when_sdkFramework() throws {
        // Given
        let dependency = ProjectDescription.TargetDependency.sdk(name: "ARKit", type: .framework, status: .required)
        let generatorPaths = GeneratorPaths(manifestDirectory: try AbsolutePath(validating: "/"), rootDirectory: "/")

        // When
        let got = try XcodeGraph.TargetDependency.from(
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

    func test_from_when_external_target_casing_differs() throws {
        // Given
        let dependency = ProjectDescription.TargetDependency.external(name: "MyLibrary")
        let generatorPaths = GeneratorPaths(manifestDirectory: try AbsolutePath(validating: "/"), rootDirectory: "/")

        // When
        let got = try XcodeGraph.TargetDependency.from(
            manifest: dependency,
            generatorPaths: generatorPaths,
            externalDependencies: ["myLibrary": [.project(target: "MyLibrary", path: "/Project")]]
        )

        // Then - should resolve successfully with case-insensitive lookup
        XCTAssertEqual(got.count, 1)
        guard case let .project(target, path, _, _) = got[0] else {
            XCTFail("Dependency should be project")
            return
        }
        XCTAssertEqual(target, "MyLibrary")
        XCTAssertEqual(path, "/Project")
    }
}

@Suite(.coverageAttribution)
struct ExternalDependencyStatusManifestMapperTests {
    private let externalDependencies: [String: [XcodeGraph.TargetDependency]] = [
        "MCP": [
            .project(target: "MCP", path: "/Packages/MCP"),
            .xcframework(path: "/MCPCore.xcframework", expectedSignature: nil, status: .required),
            .sdk(name: "libc++.tbd", status: .required),
        ],
    ]

    @Test func requiredStatusGivesThePlainExternalDependency() {
        #expect(ProjectDescription.TargetDependency.external(name: "MCP", status: .required) == .external(name: "MCP"))
    }

    @Test(arguments: [ProjectDescription.LinkingStatus.none, .optional])
    func otherStatusesGiveADependencyThatKeepsTheStatus(status: ProjectDescription.LinkingStatus) throws {
        let dependency = ProjectDescription.TargetDependency.external(name: "MCP", status: status, condition: .when([.macos]))

        #expect(dependency == .externalWithStatus(name: "MCP", status: status, condition: .when([.macos])))
        #expect(dependency.typeName == "external")
        #expect(try isCodableRoundTripable(dependency))
    }

    @Test(arguments: [ProjectDescription.LinkingStatus.none, .optional])
    func externalWithStatusGivesEveryMappedDependencyThatStatus(status: ProjectDescription.LinkingStatus) throws {
        // Given
        let dependency = ProjectDescription.TargetDependency.external(name: "MCP", status: status, condition: .when([.macos]))

        // When
        let got = try XcodeGraph.TargetDependency.from(
            manifest: dependency,
            generatorPaths: GeneratorPaths(manifestDirectory: "/", rootDirectory: "/"),
            externalDependencies: externalDependencies
        )

        // Then
        let graphStatus = XcodeGraph.LinkingStatus.from(manifest: status)
        let condition = ProjectDescription.PlatformCondition.when([.macos])?.asGraphCondition
        #expect(got == [
            .project(target: "MCP", path: "/Packages/MCP", status: graphStatus, condition: condition),
            .xcframework(path: "/MCPCore.xcframework", expectedSignature: nil, status: graphStatus, condition: condition),
            .sdk(name: "libc++.tbd", status: graphStatus, condition: condition),
        ])
    }

    @Test(arguments: [
        ProjectDescription.TargetDependency.external(name: "MCP"),
        .external(name: "MCP", status: .required),
    ])
    func externalWithoutAStatusKeepsTheRequiredStatus(dependency: ProjectDescription.TargetDependency) throws {
        // When
        let got = try XcodeGraph.TargetDependency.from(
            manifest: dependency,
            generatorPaths: GeneratorPaths(manifestDirectory: "/", rootDirectory: "/"),
            externalDependencies: externalDependencies
        )

        // Then
        #expect(got == externalDependencies["MCP"])
    }

    @Test func externalWithStatusThrowsForAnUnknownDependency() {
        #expect(throws: TargetDependencyMapperError.self) {
            try XcodeGraph.TargetDependency.from(
                manifest: .external(name: "Unknown", status: .none),
                generatorPaths: GeneratorPaths(manifestDirectory: "/", rootDirectory: "/"),
                externalDependencies: externalDependencies
            )
        }
    }
}
