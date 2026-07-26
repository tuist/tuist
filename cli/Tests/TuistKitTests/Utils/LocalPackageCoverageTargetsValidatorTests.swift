import Mockable
import Path
import Testing
import TuistCore
import TuistLoader
import XcodeGraph

@testable import TuistKit

struct LocalPackageCoverageTargetsValidatorTests {
    private let packageInfoLoader = MockPackageInfoLoading()
    private let subject: LocalPackageCoverageTargetsValidator

    init() {
        subject = LocalPackageCoverageTargetsValidator(packageInfoLoader: packageInfoLoader)
    }

    @Test func validate_keeps_references_to_graph_targets_without_loading_packages() async throws {
        // Given
        let path: AbsolutePath = "/project"
        let graph = graph(
            projectPath: path,
            packages: [.local(path: "/packageA")],
            codeCoverageTargets: [TargetReference(projectPath: path, name: "App")]
        )

        // When
        let (got, issues) = try await subject.validate(graph: graph, disableSandbox: false)

        // Then
        #expect(issues.isEmpty)
        #expect(
            got.projects[path]?.schemes.first?.testAction?.codeCoverageTargets ==
                [TargetReference(projectPath: path, name: "App")]
        )
        verify(packageInfoLoader)
            .loadPackageInfo(at: .any, disableSandbox: .any)
            .called(0)
    }

    @Test func validate_keeps_references_matching_a_package_product() async throws {
        // Given
        let path: AbsolutePath = "/project"
        let packagePath: AbsolutePath = "/packageA"
        let reference = TargetReference(projectPath: packagePath, name: "LibraryA")
        let graph = graph(
            projectPath: path,
            packages: [.local(path: packagePath)],
            codeCoverageTargets: [reference]
        )
        given(packageInfoLoader)
            .loadPackageInfo(at: .value(packagePath), disableSandbox: .any)
            .willReturn(.test(products: [
                PackageInfo.Product(name: "LibraryA", type: .library(.automatic), targets: ["LibraryACore"]),
            ]))

        // When
        let (got, issues) = try await subject.validate(graph: graph, disableSandbox: false)

        // Then
        #expect(issues.isEmpty)
        #expect(got.projects[path]?.schemes.first?.testAction?.codeCoverageTargets == [reference])
    }

    @Test func validate_drops_references_not_matching_a_package_product() async throws {
        // Given
        let path: AbsolutePath = "/project"
        let packagePath: AbsolutePath = "/packageA"
        let graph = graph(
            projectPath: path,
            packages: [.local(path: packagePath)],
            // The name of the package target backing the product, not the product itself.
            codeCoverageTargets: [TargetReference(projectPath: packagePath, name: "LibraryACore")]
        )
        given(packageInfoLoader)
            .loadPackageInfo(at: .value(packagePath), disableSandbox: .any)
            .willReturn(.test(products: [
                PackageInfo.Product(name: "LibraryA", type: .library(.automatic), targets: ["LibraryACore"]),
            ]))

        // When
        let (got, issues) = try await subject.validate(graph: graph, disableSandbox: false)

        // Then
        #expect(got.projects[path]?.schemes.first?.testAction?.codeCoverageTargets == [])
        #expect(
            issues ==
                [LintingIssue(
                    reason: "The target 'LibraryACore' specified in SomeScheme code coverage targets list isn't a product of the package at '../packageA'. The reference will be ignored.",
                    severity: .warning
                )]
        )
    }

    @Test func validate_drops_references_to_a_product_of_another_package() async throws {
        // Given
        let path: AbsolutePath = "/project"
        let packageAPath: AbsolutePath = "/packageA"
        let packageBPath: AbsolutePath = "/packageB"
        let graph = graph(
            projectPath: path,
            packages: [.local(path: packageAPath), .local(path: packageBPath)],
            // A product of package B referenced through package A's path.
            codeCoverageTargets: [TargetReference(projectPath: packageAPath, name: "LibraryB")]
        )
        given(packageInfoLoader)
            .loadPackageInfo(at: .value(packageAPath), disableSandbox: .any)
            .willReturn(.test(products: [
                PackageInfo.Product(name: "LibraryA", type: .library(.automatic), targets: ["LibraryACore"]),
            ]))

        // When
        let (got, issues) = try await subject.validate(graph: graph, disableSandbox: false)

        // Then
        #expect(got.projects[path]?.schemes.first?.testAction?.codeCoverageTargets == [])
        #expect(
            issues ==
                [LintingIssue(
                    reason: "The target 'LibraryB' specified in SomeScheme code coverage targets list isn't a product of the package at '../packageA'. The reference will be ignored.",
                    severity: .warning
                )]
        )
    }

    @Test func validate_keeps_references_that_are_not_local_packages() async throws {
        // Given
        let path: AbsolutePath = "/project"
        let unknownReference = TargetReference(projectPath: "/unknown", name: "Unknown")
        let graph = graph(
            projectPath: path,
            packages: [.local(path: "/packageA")],
            codeCoverageTargets: [unknownReference]
        )

        // When
        let (got, issues) = try await subject.validate(graph: graph, disableSandbox: false)

        // Then
        #expect(issues.isEmpty)
        #expect(got.projects[path]?.schemes.first?.testAction?.codeCoverageTargets == [unknownReference])
        verify(packageInfoLoader)
            .loadPackageInfo(at: .any, disableSandbox: .any)
            .called(0)
    }

    @Test func validate_workspace_schemes() async throws {
        // Given
        let path: AbsolutePath = "/project"
        let packagePath: AbsolutePath = "/packageA"
        var graph = graph(
            projectPath: path,
            packages: [.local(path: packagePath)],
            codeCoverageTargets: []
        )
        graph.workspace.schemes = [
            scheme(
                projectPath: path,
                codeCoverageTargets: [TargetReference(projectPath: packagePath, name: "LibraryACore")]
            ),
        ]
        given(packageInfoLoader)
            .loadPackageInfo(at: .value(packagePath), disableSandbox: .any)
            .willReturn(.test(products: [
                PackageInfo.Product(name: "LibraryA", type: .library(.automatic), targets: ["LibraryACore"]),
            ]))

        // When
        let (got, issues) = try await subject.validate(graph: graph, disableSandbox: false)

        // Then
        #expect(got.workspace.schemes.first?.testAction?.codeCoverageTargets == [])
        #expect(issues.count == 1)
    }

    private func graph(
        projectPath: AbsolutePath,
        packages: [Package],
        codeCoverageTargets: [TargetReference]
    ) -> Graph {
        let project = Project.test(
            path: projectPath,
            targets: [
                Target.test(name: "App"),
                Target.test(name: "AppTests"),
            ],
            packages: packages,
            schemes: [scheme(projectPath: projectPath, codeCoverageTargets: codeCoverageTargets)]
        )
        return Graph.test(
            path: projectPath,
            projects: [projectPath: project]
        )
    }

    private func scheme(
        projectPath: AbsolutePath,
        codeCoverageTargets: [TargetReference]
    ) -> Scheme {
        Scheme.test(
            name: "SomeScheme",
            buildAction: .init(targets: [TargetReference(projectPath: projectPath, name: "App")]),
            testAction: .test(
                targets: [TestableTarget(target: TargetReference(projectPath: projectPath, name: "AppTests"))],
                coverage: true,
                codeCoverageTargets: codeCoverageTargets
            )
        )
    }
}
