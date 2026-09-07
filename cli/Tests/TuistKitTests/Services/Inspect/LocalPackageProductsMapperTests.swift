import Foundation
import Mockable
import Path
import Testing
import TSCUtility
import TuistLoader
import TuistSupport
import TuistTesting
import XcodeGraph

@testable import TuistInspectCommand

struct LocalPackageProductsMapperTests {
    private let manifestLoader = MockManifestLoading()
    private let subject: LocalPackageProductsMapper

    init() {
        subject = LocalPackageProductsMapper(manifestLoader: manifestLoader)
    }

    @Test func mapReplacesPackageProductsWithTheTargetsTheyVend() async throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let packagePath = try AbsolutePath(validating: "/project/Packages/Feature")
        let app = Target.test(name: "App", product: .app)
        let graph = Graph.test(
            path: path,
            projects: [
                path: Project.test(path: path, targets: [app], packages: [.local(path: packagePath)]),
                packagePath: Project.test(
                    path: packagePath,
                    targets: [Target.test(name: "FeatureCore"), Target.test(name: "FeatureUI")]
                ),
            ],
            dependencies: [
                .target(name: app.name, path: path): [
                    .packageProduct(path: path, product: "Feature", type: .runtime),
                ],
            ]
        )
        given(manifestLoader).loadPackage(at: .value(packagePath), disableSandbox: .value(false))
            .willReturn(
                packageInfo(products: [.init(name: "Feature", type: .library(.automatic), targets: ["FeatureCore", "FeatureUI"])])
            )

        // When
        let got = try await subject.map(graph: graph, disableSandbox: false)

        // Then
        #expect(got.dependencies == [
            .target(name: app.name, path: path): [
                .target(name: "FeatureCore", path: packagePath),
                .target(name: "FeatureUI", path: packagePath),
            ],
        ])
    }

    @Test func mapKeepsProductsThatNoLocalPackageVends() async throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let packagePath = try AbsolutePath(validating: "/project/Packages/Feature")
        let app = Target.test(name: "App", product: .app)
        let graph = Graph.test(
            path: path,
            projects: [
                path: Project.test(path: path, targets: [app], packages: [.local(path: packagePath)]),
                packagePath: Project.test(path: packagePath, targets: [Target.test(name: "FeatureCore")]),
            ],
            dependencies: [
                .target(name: app.name, path: path): [
                    .packageProduct(path: path, product: "Alamofire", type: .runtime),
                ],
            ]
        )
        given(manifestLoader).loadPackage(at: .value(packagePath), disableSandbox: .value(false))
            .willReturn(packageInfo(products: [.init(name: "Feature", type: .library(.automatic), targets: ["FeatureCore"])]))

        // When
        let got = try await subject.map(graph: graph, disableSandbox: false)

        // Then
        #expect(got.dependencies == graph.dependencies)
    }

    @Test func mapDoesntLoadPackagesThatAreNotPartOfTheGraph() async throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let packagePath = try AbsolutePath(validating: "/project/Packages/Feature")
        let app = Target.test(name: "App", product: .app)
        let graph = Graph.test(
            path: path,
            projects: [
                path: Project.test(path: path, targets: [app], packages: [.local(path: packagePath)]),
            ],
            dependencies: [
                .target(name: app.name, path: path): [
                    .packageProduct(path: path, product: "Feature", type: .runtime),
                ],
            ]
        )

        // When
        let got = try await subject.map(graph: graph, disableSandbox: false)

        // Then
        #expect(got.dependencies == graph.dependencies)
        verify(manifestLoader).loadPackage(at: .any, disableSandbox: .any).called(0)
    }

    private func packageInfo(products: [PackageInfo.Product]) -> PackageInfo {
        PackageInfo(
            name: "Feature",
            products: products,
            targets: [],
            traits: nil,
            dependencies: [],
            platforms: [],
            cLanguageStandard: nil,
            cxxLanguageStandard: nil,
            swiftLanguageVersions: nil,
            toolsVersion: Version(5, 9, 0)
        )
    }
}
