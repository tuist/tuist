import Foundation
import TuistCore
import TuistLoader
import TuistSupport
import Testing
import ServiceContextModule

@testable import TuistCoreTesting
@testable import TuistKit
@testable import TuistSupportTesting

struct ManifestGraphLoaderIntegrationTests {
    var subject: ManifestGraphLoader!

    init() {
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

    @Test(.mocked, .temporaryFixture("WorkspaceWithPlugins"))
    func test_load_workspace() async throws {
        // When
        let (result, _, _, _) = try await subject.load(path: ServiceContext.current!.temporaryFixtureDirectory)

        // Then
        #expect(result.workspace.name == "Workspace")
        #expect(result.projects.values.map(\.name).sorted() == [
            "App",
            "FrameworkA",
            "FrameworkB",
        ])
    }

    @Test(.mocked, .temporaryFixture("WorkspaceWithPlugins"))
    func test_load_project() async throws {
        // When
        let (result, _, _, _) = try await subject.load(path: ServiceContext.current!.temporaryFixtureDirectory.appending(component: "App"))

        // Then
        #expect(result.workspace.name == "App")
        #expect(result.projects.values.map(\.name).sorted() == [
            "App",
            "FrameworkA",
            "FrameworkB",
        ])
    }
}
