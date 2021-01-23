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
    private var temporaryDirectory: AbsolutePath!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = try temporaryPath()
        subject = .init(
            temporaryDirectory: temporaryDirectory
        )
    }

    override func tearDown() {
        super.tearDown()
        subject = nil
    }

    func test_map() throws {
        // Given
        let workspace = Workspace.test(
            path: temporaryDirectory,
            name: "A"
        )

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
                path: temporaryDirectory,
                name: "A"
            )
        )
        XCTAssertEqual(
            gotSideEffects,
            [
                .directory(
                    DirectoryDescriptor(
                        path: temporaryDirectory,
                        state: .present
                    )
                ),
            ]
        )
    }
}
