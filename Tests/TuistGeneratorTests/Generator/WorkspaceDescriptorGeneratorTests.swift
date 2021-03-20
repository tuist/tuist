import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistGraph
import TuistGraphTesting
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

        let workspace = Workspace.test(
            xcWorkspacePath: temporaryPath.appending(component: "Test.xcworkspace"),
            additionalFiles: additionalFiles
        )
        let graph = ValueGraph.test(
            path: temporaryPath,
            workspace: workspace
        )

        // When
        let graphTraverser = ValueGraphTraverser(graph: graph)
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
        let graph = ValueGraph.test(
            path: temporaryPath,
            workspace: workspace
        )
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        XCTAssertNoThrow(
            try subject.generate(graphTraverser: graphTraverser)
        )
    }

    func test_generate_workspaceStructureWithProjects() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let target = anyTarget()
        let project = Project.test(
            path: temporaryPath,
            sourceRootPath: temporaryPath,
            xcodeProjPath: temporaryPath.appending(component: "Test.xcodeproj"),
            name: "Test",
            settings: .default,
            targets: [target]
        )

        let workspace = Workspace.test(
            xcWorkspacePath: temporaryPath.appending(component: "Test.xcworkspace"),
            projects: [project.path]
        )

        let graph = ValueGraph.test(
            workspace: workspace,
            projects: [project.path: project],
            targets: [
                project.path: [
                    target.name: target,
                ],
            ]
        )
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let result = try subject.generate(graphTraverser: graphTraverser)

        // Then
        let xcworkspace = result.xcworkspace
        XCTAssertEqual(xcworkspace.data.children, [
            .file(.init(location: .group("Test.xcodeproj"))),
        ])
    }

    // MARK: - Helpers

    func anyTarget(dependencies: [TargetDependency] = []) -> Target {
        Target.test(
            infoPlist: nil,
            entitlements: nil,
            settings: nil,
            dependencies: dependencies
        )
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
