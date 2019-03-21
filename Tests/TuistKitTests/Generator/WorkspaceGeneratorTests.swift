import Basic
import Foundation
import xcodeproj
import XCTest
@testable import TuistCoreTesting
@testable import TuistKit

final class WorkspaceGeneratorTests: XCTestCase {
    var subject: WorkspaceGenerator!
    var path: AbsolutePath!
    var fileHandler: MockFileHandler!

    override func setUp() {
        super.setUp()

        do {
            fileHandler = try MockFileHandler()
            path = fileHandler.currentPath

            let projectDirectoryHelper = ProjectDirectoryHelper(environmentController: try MockEnvironmentController(),
                                                                fileHandler: fileHandler)

            subject = WorkspaceGenerator(
                system: MockSystem(),
                printer: MockPrinter(),
                projectDirectoryHelper: projectDirectoryHelper,
                fileHandler: fileHandler
            )

        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    // MARK: - Tests

    func test_generate_workspaceStructure() throws {
        // Given
        try createFiles([
            "README.md",
            "Documentation/README.md",
            "Website/index.html",
            "Website/about.html",
        ])

        let additionalFiles: [Workspace.Element] = [
            .file(path: path.appending(RelativePath("README.md"))),
            .file(path: path.appending(RelativePath("Documentation/README.md"))),
            .folderReference(path: path.appending(RelativePath("Website"))),
        ]

        let graph = Graph.test(entryPath: path)
        let workspace = Workspace.test(additionalFiles: additionalFiles)

        // When
        let workspacePath = try subject.generate(workspace: workspace,
                                                 path: path,
                                                 graph: graph,
                                                 options: GenerationOptions())

        // Then
        let xcworkspace = try XCWorkspace(pathString: workspacePath.asString)
        XCTAssertEqual(xcworkspace.data.children, [
            .group(.init(location: .group("Documentation"), name: "Documentation", children: [
                .file(.init(location: .group("README.md"))),
            ])),
            .file(.init(location: .group("README.md"))),
            .file(.init(location: .group("Website"))),
        ])
    }

    func test_generate_workspaceStructureWithProjects() throws {
        // Given
        let target = anyTarget()
        let project = Project.test(path: path,
                                   name: "Test",
                                   settings: nil,
                                   targets: [target])
        let graph = createGraph(project: project,
                                dependencies: [(target, [])])
        let workspace = Workspace.test(projects: [project.path])

        // When
        let workspacePath = try subject.generate(workspace: workspace,
                                                 path: path,
                                                 graph: graph,
                                                 options: GenerationOptions())

        // Then
        let xcworkspace = try XCWorkspace(pathString: workspacePath.asString)
        XCTAssertEqual(xcworkspace.data.children, [
            .file(.init(location: .group("Test.xcodeproj"))),
        ])
    }

    // MARK: - Helpers

    func anyTarget() -> Target {
        return Target.test(infoPlist: nil,
                           entitlements: nil,
                           settings: nil)
    }

    @discardableResult
    func createFiles(_ files: [String]) throws -> [AbsolutePath] {
        let paths = files.map { fileHandler.currentPath.appending(RelativePath($0)) }
        try paths.forEach {
            try fileHandler.touch($0)
        }
        return paths
    }

    private func createTargetNodes(project: Project,
                                   dependencies: [(target: Target, dependencies: [Target])]) -> [TargetNode] {
        let nodesCache = Dictionary(uniqueKeysWithValues: dependencies.map {
            ($0.target.name, TargetNode(project: project,
                                        target: $0.target,
                                        dependencies: []))
        })

        return dependencies.map {
            let node = nodesCache[$0.target.name]!
            node.dependencies = $0.dependencies.map { nodesCache[$0.name]! }
            return node
        }
    }

    private func createGraph(project: Project,
                             dependencies: [(target: Target, dependencies: [Target])]) -> Graph {
        let targetNodes = createTargetNodes(project: project, dependencies: dependencies)

        let cache = GraphLoaderCache()
        let graph = Graph.test(name: project.name,
                               entryPath: project.path,
                               cache: cache,
                               entryNodes: targetNodes)

        targetNodes.forEach { cache.add(targetNode: $0) }
        cache.add(project: project)

        return graph
    }
}

extension XCWorkspaceDataElement: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case let .file(file):
            return file.location.path
        case let .group(group):
            return group.debugDescription
        }
    }
}

extension XCWorkspaceDataGroup: CustomDebugStringConvertible {
    public var debugDescription: String {
        return children.debugDescription
    }
}
