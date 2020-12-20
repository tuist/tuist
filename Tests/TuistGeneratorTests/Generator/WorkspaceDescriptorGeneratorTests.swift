import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistSupport
import XcodeProj
import XCTest
@testable import TuistGenerator
@testable import TuistSupportTesting

final class WorkspaceDescriptorGeneratorTests: TuistUnitTestCase {
    var subject: WorkspaceDescriptorGenerator!

    override func setUp() {
        super.setUp()
        system.swiftVersionStub = { "5.2" }
        subject = WorkspaceDescriptorGenerator(config: .init(projectGenerationContext: .serial))
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    // MARK: - Tests

    func test_generate_workspaceStructure() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        try createFiles([
            "README.md",
            "Documentation/README.md",
            "Website/index.html",
            "Website/about.html",
        ])

        let additionalFiles: [FileElement] = [
            .file(path: temporaryPath.appending(RelativePath("README.md"))),
            .file(path: temporaryPath.appending(RelativePath("Documentation/README.md"))),
            .folderReference(path: temporaryPath.appending(RelativePath("Website"))),
        ]

        let workspace = Workspace.test(additionalFiles: additionalFiles)
        let graph = Graph.test(entryPath: temporaryPath, workspace: workspace)

        // When
        let valueGraph = ValueGraph(graph: graph)
        let graphTraverser = ValueGraphTraverser(graph: valueGraph)
        let result = try subject.generate(graphTraverser: graphTraverser)

        // Then
        let xcworkspace = result.xcworkspace
        XCTAssertEqual(xcworkspace.data.children, [
            .group(.init(location: .group("Documentation"), name: "Documentation", children: [
                .file(.init(location: .group("README.md"))),
            ])),
            .file(.init(location: .group("README.md"))),
            .file(.init(location: .group("Website"))),
        ])
    }

    func test_generate_workspaceStructure_noWorkspaceData() throws {
        // Given
        let name = "test"
        let temporaryPath = try self.temporaryPath()
        try FileHandler.shared.createFolder(temporaryPath.appending(component: "\(name).xcworkspace"))
        let workspace = Workspace.test(name: name)
        let graph = Graph.test(entryPath: temporaryPath, workspace: workspace)
        let valueGraph = ValueGraph(graph: graph)
        let graphTraverser = ValueGraphTraverser(graph: valueGraph)

        // When
        XCTAssertNoThrow(
            try subject.generate(graphTraverser: graphTraverser)
        )
    }

    func test_generate_workspaceStructureWithProjects() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let target = anyTarget()
        let project = Project.test(path: temporaryPath,
                                   sourceRootPath: temporaryPath,
                                   xcodeProjPath: temporaryPath.appending(component: "Test.xcodeproj"),
                                   name: "Test",
                                   settings: .default,
                                   targets: [target])

        let workspace = Workspace.test(projects: [project.path])
        let graph = Graph.create(project: project,
                                 dependencies: [(target, [])])
        let valueGraph = ValueGraph(graph: graph.with(workspace: workspace))
        let graphTraverser = ValueGraphTraverser(graph: valueGraph)

        // When
        let result = try subject.generate(graphTraverser: graphTraverser)

        // Then
        let xcworkspace = result.xcworkspace
        XCTAssertEqual(xcworkspace.data.children, [
            .file(.init(location: .group("Test.xcodeproj"))),
        ])
    }

    // MARK: - Helpers

    func anyTarget(dependencies: [Dependency] = []) -> Target {
        Target.test(infoPlist: nil,
                    entitlements: nil,
                    settings: nil,
                    dependencies: dependencies)
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
        children.debugDescription
    }
}
