import FileSystem
import FileSystemTesting
import Foundation
import Testing
import TuistCore
import TuistLoader
import TuistSupport
@testable import TuistKit
@testable import TuistTesting

@Suite(.withMockedDependencies()) struct ManifestGraphLoaderIntegrationTests {
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

    @Test(.withFixture("WorkspaceWithPlugins")) func load_workspace() async throws {
        // Given
        let path = try #require(TuistTest.fixtureDirectory)

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

    @Test(.withFixture("WorkspaceWithPlugins")) func load_project() async throws {
        // Given
        let path = try #require(TuistTest.fixtureDirectory)
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
