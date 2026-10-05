import FileSystem
import FileSystemTesting
import Foundation
import Testing
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
}

struct ManifestGraphLoaderCoverageAttributionIntegrationTests {
    @Test(.inTemporaryDirectory)
    func load_whenCoverageIsAttributedToTestsWithoutAPackageManifest() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()
        try await fileSystem.writeText(
            """
            import ProjectDescription

            let tuist = Tuist(
                testInsights: .testInsights(coverage: .coverage(attributeToTests: true)),
                project: .tuist()
            )
            """,
            at: path.appending(component: "Tuist.swift")
        )
        try await fileSystem.writeText(
            """
            import ProjectDescription

            let project = Project(
                name: "App",
                targets: [
                    .target(name: "App", destinations: .macOS, product: .framework, bundleId: "dev.tuist.App"),
                    .target(
                        name: "AppTests",
                        destinations: .macOS,
                        product: .unitTests,
                        bundleId: "dev.tuist.AppTests",
                        dependencies: [.target(name: "App")]
                    ),
                ]
            )
            """,
            at: path.appending(component: "Project.swift")
        )
        let subject = ManifestGraphLoader(
            manifestLoader: ManifestLoader(),
            workspaceMapper: SequentialWorkspaceMapper(mappers: []),
            graphMapper: SequentialGraphMapper([])
        )

        // When / Then
        await #expect(throws: TestCoverageAttributionLinkerError.missingPackageManifest) {
            try await subject.load(path: path, disableSandbox: true)
        }
    }
}
