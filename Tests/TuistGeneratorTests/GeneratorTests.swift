import Basic
import XCTest
@testable import TuistCoreTesting
@testable import TuistGenerator

class GeneratorTests: XCTestCase {
    var workspaceGenerator: MockWorkspaceGenerator!
    var graphLoader: MockGraphLoader!
    var subject: Generator!

    override func setUp() {
        graphLoader = MockGraphLoader()
        workspaceGenerator = MockWorkspaceGenerator()

        subject = Generator(graphLoader: graphLoader,
                            workspaceGenerator: workspaceGenerator)
    }

    // MARK: - Tests

    func test_generateWorkspace_mergeGraphProjects() throws {
        // Given
        let workpsace = Workspace.test(projects: [
            "/path/to/A",
            "/path/to/B",
        ])
        let graph = createGraph(with: [
            Project.test(path: "/path/to/A"),
            Project.test(path: "/path/to/B"),
            Project.test(path: "/path/to/C"),
        ])
        graphLoader.loadWorkspaceStub = { _ in
            (graph, workpsace)
        }

        // When
        _ = try subject.generateWorkspace(at: "/path/to",
                                          config: GeneratorConfig(),
                                          workspaceFiles: [])

        // Then
        let projectPaths = workspaceGenerator.generateWorkspaces.flatMap {
            $0.projects
        }
        XCTAssertEqual(Set(projectPaths), Set([
            "/path/to/A",
            "/path/to/B",
            "/path/to/C",
        ]))
    }

    func test_generateProject_workspaceIncludesDependencies() throws {
        // Given
        let project = Project.test(path: "/path/to/A")
        let graph = createGraph(with: [
            Project.test(path: "/path/to/A"),
            Project.test(path: "/path/to/B"),
            Project.test(path: "/path/to/C"),
        ])
        graphLoader.loadProjectStub = { _ in
            (graph, project)
        }

        // When
        _ = try subject.generateProject(at: "/path/to",
                                        config: GeneratorConfig(),
                                        workspaceFiles: [])

        // Then
        let projectPaths = workspaceGenerator.generateWorkspaces.flatMap {
            $0.projects
        }
        XCTAssertEqual(Set(projectPaths), Set([
            "/path/to/A",
            "/path/to/B",
            "/path/to/C",
        ]))
    }

    func test_generateProject_workspaceFiles() throws {
        // Given
        let project = Project.test(path: "/path/to/A")

        let workspaceFiles: [AbsolutePath] = [
            "/path/to/D",
            "/path/to/E",
        ]

        let graph = createGraph(with: [])
        graphLoader.loadProjectStub = { _ in
            (graph, project)
        }

        // When
        _ = try subject.generateProject(at: "/path/to",
                                        config: GeneratorConfig(),
                                        workspaceFiles: workspaceFiles)

        // Then
        let additionalFiles = workspaceGenerator.generateWorkspaces.flatMap {
            $0.additionalFiles
        }
        XCTAssertEqual(additionalFiles, [
            .file(path: "/path/to/D"),
            .file(path: "/path/to/E"),
        ])
    }

    func test_generateWorkspace_workspaceFiles() throws {
        // Given
        let workpsace = Workspace.test(projects: [],
                                       additionalFiles: [
                                           .file(path: "/path/to/a"),
                                           .file(path: "/path/to/b"),
                                           .file(path: "/path/to//c"),
                                       ])
        let graph = createGraph(with: [])
        graphLoader.loadWorkspaceStub = { _ in
            (graph, workpsace)
        }

        // When
        _ = try subject.generateWorkspace(at: "/path/to",
                                          config: GeneratorConfig(),
                                          workspaceFiles: [
                                              "/path/to/D",
                                              "/path/to/E",
                                          ])

        // Then
        let additionalFiles = workspaceGenerator.generateWorkspaces.flatMap {
            $0.additionalFiles
        }
        XCTAssertEqual(additionalFiles, [
            .file(path: "/path/to/a"),
            .file(path: "/path/to/b"),
            .file(path: "/path/to/c"),
            .file(path: "/path/to/D"),
            .file(path: "/path/to/E"),
        ])
    }

    // MARK: - Helpers

    func createGraph(with projects: [Project]) -> Graph {
        let cache = GraphLoaderCache()
        projects.forEach { cache.add(project: $0) }

        let graph = Graph.test(cache: cache)
        return graph
    }
}
