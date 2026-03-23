import Foundation
import TuistCore
import TuistLoader
import TuistSupport
import FileSystemTesting
import Testing
@testable import TuistKit
@testable import TuistTesting

struct ManifestGraphLoaderIntegrationTests {
    var subject: ManifestGraphLoader!

    init() throws {
        let manifestLoader = ManifestLoader()
        let workspaceMapper = SequentialWorkspaceMapper(mappers: [])
        let graphMapper = SequentialGraphMapper([])
        subject = ManifestGraphLoader(
            manifestLoader: manifestLoader,
            workspaceMapper: workspaceMapper,
            graphMapper: graphMapper
        )
    }

    // MARK: - Tests

    @Test func test_load_workspace() async throws {
        // Given
        let path = try await temporaryFixture("WorkspaceWithPlugins")

        // When
        let (result, _, _, _) = try await subject.load(path: path, disableSandbox: true)

        // Then
        #expect(result.workspace.name == "Workspace")
        #expect(result.projects.values.map(\.name).sorted() == [
            "App",
            "FrameworkA",
            "FrameworkB",
        ])
    }

    @Test func test_load_project() async throws {
        // Given
        let path = try await temporaryFixture("WorkspaceWithPlugins")
            .appending(component: "App")

        // When
        let (result, _, _, _) = try await subject.load(path: path, disableSandbox: true)

        // Then
        #expect(result.workspace.name == "App")
        #expect(result.projects.values.map(\.name).sorted() == [
            "App",
            "FrameworkA",
            "FrameworkB",
        ])
    }
}
