import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistAutomation
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class AutomationPathWorkspaceMapperTests: TuistUnitTestCase {
    private var subject: AutomationPathWorkspaceMapper!
    private var contentHasher: MockContentHasher!

    override func setUp() {
        super.setUp()
        contentHasher = .init()
        subject = .init(
            contentHasher: contentHasher
        )
    }

    override func tearDown() {
        super.tearDown()
        contentHasher = nil
        subject = nil
    }

    func test_map() throws {
        // Given
        let workspacePath = try temporaryPath()
        contentHasher.hashStub = { _ in
            workspacePath.basename
        }
        let workspace = Workspace.test(
            path: workspacePath,
            name: "A"
        )
        let projectsDirectory = environment.projectsCacheDirectory
            .appending(component: "A-\(workspacePath.basename)")

        // When
        let (gotWorkspaceWithProjects, gotSideEffects) = try subject.map(
            workspace: WorkspaceWithProjects(
                workspace: workspace,
                projects: []
            )
        )

        // Then
        XCTAssertEqual(
            gotWorkspaceWithProjects.workspace,
            Workspace.test(
                path: projectsDirectory,
                name: "A"
            )
        )
        XCTAssertEqual(
            gotSideEffects,
            [
                .directory(
                    DirectoryDescriptor(
                        path: projectsDirectory,
                        state: .present
                    )
                ),
            ]
        )
    }
}
