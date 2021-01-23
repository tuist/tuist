import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import TuistGraph
import XCTest

@testable import TuistAutomation
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class AutomationPathWorkspaceMapperTests: TuistUnitTestCase {
    private var subject: AutomationPathWorkspaceMapper!
    private var workspaceDirectory: AbsolutePath!

    override func setUpWithError() throws {
        try super.setUpWithError()
        workspaceDirectory = try temporaryPath()
        subject = .init(
            workspaceDirectory: workspaceDirectory
        )
    }

    override func tearDown() {
        super.tearDown()
        subject = nil
    }

    func test_map() throws {
        // Given
        let projectPath = try temporaryPath()
        let project = Project.test(
            path: projectPath,
            sourceRootPath: projectPath,
            xcodeProjPath: projectPath.appending(component: "A.xcodeproj"),
            name: "A"
        )

        let workspace = Workspace.test(
            path: workspaceDirectory,
            name: "A"
        )

        // When
        let (gotWorkspaceWithProjects, gotSideEffects) = try subject.map(
            workspace: WorkspaceWithProjects(
                workspace: workspace,
                projects: [
                    project,
                ]
            )
        )

        // Then
        XCTAssertEqual(
            gotWorkspaceWithProjects.workspace,
            Workspace.test(
                path: workspaceDirectory,
                name: "A"
            )
        )
        XCTAssertEqual(
            gotWorkspaceWithProjects.projects,
            [
                Project.test(
                    path: projectPath,
                    sourceRootPath: workspaceDirectory,
                    xcodeProjPath: workspaceDirectory.appending(component: "A.xcodeproj"),
                    name: "A"
                ),
            ]
        )
        XCTAssertEqual(
            gotSideEffects,
            [
                .directory(
                    DirectoryDescriptor(
                        path: workspaceDirectory,
                        state: .present
                    )
                ),
            ]
        )
    }
}
