import Foundation
import TuistCore
import TuistLoader
import TuistSupport
import XcodeGraph
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

    func test_load_tracks_mapped_graph_in_run_metadata_storage() async throws {
        // Given
        let path = try await temporaryFixture("WorkspaceWithPlugins")
        let runMetadataStorage = RunMetadataStorage()
        let graphMapper = AnyGraphMapper { graph in
            var graph = graph
            let projectEntry = try self.XCTUnwrap(graph.projects.first { $0.value.targets["App"] != nil })
            var project = projectEntry.value
            var target = try self.XCTUnwrap(project.targets["App"])

            target.name = "MappedApp"
            project.targets.removeValue(forKey: "App")
            project.targets[target.name] = target
            graph.projects[projectEntry.key] = project

            return (graph, [], MapperEnvironment())
        }
        subject = ManifestGraphLoader(
            manifestLoader: ManifestLoader(),
            workspaceMapper: SequentialWorkspaceMapper(mappers: []),
            graphMapper: graphMapper
        )

        // When
        try await RunMetadataStorage.$current.withValue(runMetadataStorage) {
            let (graph, _, _, _) = try await subject.load(path: path, disableSandbox: true)

            // Then
            XCTAssertTrue(graph.projects.values.flatMap(\.targets.keys).contains("MappedApp"))
            let trackedGraph = await runMetadataStorage.graph
            let unwrappedTrackedGraph = try XCTUnwrap(trackedGraph)
            XCTAssertTrue(unwrappedTrackedGraph.projects.values.flatMap(\.targets.keys).contains("MappedApp"))
        }
    }
}
