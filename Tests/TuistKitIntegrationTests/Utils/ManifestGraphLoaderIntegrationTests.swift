import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistLoader
import TuistSupport
import XCTest
@testable import TuistCoreTesting
@testable import TuistKit
@testable import TuistSupportTesting

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
        let path = try temporaryFixture("WorkspaceWithPlugins")

        // When
        let (result, _) = try await subject.load(path: path)

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
        let path = try temporaryFixture("WorkspaceWithPlugins")
            .appending(component: "App")

        // When
        let (result, _) = try await subject.load(path: path)

        // Then
        XCTAssertEqual(result.workspace.name, "App")
        XCTAssertEqual(result.projects.values.map(\.name).sorted(), [
            "App",
            "FrameworkA",
            "FrameworkB",
        ])
    }
}
