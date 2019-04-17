import Basic
import Foundation
import XcodeProj
import XCTest
@testable import TuistCoreTesting
@testable import TuistGenerator

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
        try fileHandler.createFiles([
            "README.md",
            "Documentation/README.md",
            "Website/index.html",
            "Website/about.html",
        ])

        let additionalFiles: [FileElement] = [
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
        let xcworkspace = try XCWorkspace(pathString: workspacePath.pathString)
        XCTAssertEqual(xcworkspace.data.children, [
            .group(.init(location: .group("Documentation"), name: "Documentation", children: [
                .file(.init(location: .group("README.md"))),
            ])),
            .file(.init(location: .group("README.md"))),
            .file(.init(location: .group("Website"))),
        ])
    }

    func test_generate_workspaceStructure_noWorkspaceData() throws {
        let name = "test"

        // Given
        try fileHandler.createFolder(fileHandler.currentPath.appending(component: "\(name).xcworkspace"))

        let graph = Graph.test(entryPath: path)
        let workspace = Workspace.test(name: name)

        // When
        XCTAssertNoThrow(
            try subject.generate(workspace: workspace,
                                 path: path,
                                 graph: graph,
                                 options: GenerationOptions())
        )
    }

    func test_generate_workspaceStructureWithProjects() throws {
        // Given
        let target = anyTarget()
        let project = Project.test(path: path,
                                   name: "Test",
                                   settings: .default,
                                   targets: [target])
        let graph = Graph.create(project: project,
                                 dependencies: [(target, [])])
        let workspace = Workspace.test(projects: [project.path])

        // When
        let workspacePath = try subject.generate(workspace: workspace,
                                                 path: path,
                                                 graph: graph,
                                                 options: GenerationOptions())

        // Then
        let xcworkspace = try XCWorkspace(pathString: workspacePath.pathString)
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
