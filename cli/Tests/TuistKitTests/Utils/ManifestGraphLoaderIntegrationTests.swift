import Foundation
import TuistCore
import TuistLoader
import TuistSupport
import XCTest
@testable import TuistKit
@testable import TuistTesting

final class ManifestGraphLoaderIntegrationTests: TuistTestCase {
    var subject: ManifestGraphLoader!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let manifestLoader = ManifestLoader()
        let workspaceMapper = SequentialWorkspaceMapper(mappers: [])
        let graphMapper = SequentialGraphMapper([])
        subject = ManifestGraphLoader(
            manifestLoader: manifestLoader,
            workspaceMapper: workspaceMapper,
            graphMapper: graphMapper
        )
    }

    override func tearDownWithError() throws {
        subject = nil
        try super.tearDownWithError()
    }

    // MARK: - Tests

    func test_load_workspace() async throws {
        // Given
        let path = try await temporaryFixture("WorkspaceWithPlugins")

        // When
        let (result, _, _, _) = try await subject.load(path: path, disableSandbox: true)

        // Then
        XCTAssertEqual(result.workspace.name, "Workspace")
        XCTAssertEqual(result.projects.values.map(\.name).sorted(), [
            "App",
            "FrameworkA",
            "FrameworkB",
        ])
    }

    func test_load_project() async throws {
        // Given
        let path = try await temporaryFixture("WorkspaceWithPlugins")
            .appending(component: "App")

        // When
        let (result, _, _, _) = try await subject.load(path: path, disableSandbox: true)

        // Then
        XCTAssertEqual(result.workspace.name, "App")
        XCTAssertEqual(result.projects.values.map(\.name).sorted(), [
            "App",
            "FrameworkA",
            "FrameworkB",
        ])
    }

    func test_load_whenCoverageIsAttributedToTestsWithoutAPackageManifest() async throws {
        // Given
        let path = try temporaryPath()
        try await createFiles(["Sources/App.swift", "Tests/AppTests.swift"])
        try """
        import ProjectDescription

        let tuist = Tuist(
            testInsights: .testInsights(coverage: .coverage(attributeToTests: true)),
            project: .tuist()
        )
        """.write(to: path.appending(component: "Tuist.swift").url, atomically: true, encoding: .utf8)
        try """
        import ProjectDescription

        let project = Project(
            name: "App",
            targets: [
                .target(name: "App", destinations: .macOS, product: .app, bundleId: "dev.tuist.App", sources: ["Sources/**"]),
                .target(
                    name: "AppTests",
                    destinations: .macOS,
                    product: .unitTests,
                    bundleId: "dev.tuist.AppTests",
                    sources: ["Tests/**"],
                    dependencies: [.target(name: "App")]
                ),
            ]
        )
        """.write(to: path.appending(component: "Project.swift").url, atomically: true, encoding: .utf8)

        // When / Then
        await XCTAssertThrowsSpecific(
            { try await self.subject.load(path: path, disableSandbox: true) },
            TestCoverageAttributionLinkerError.missingPackageManifest
        )
    }
}
