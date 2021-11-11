import Foundation
import TSCBasic
import TuistCache
import TuistCloud
import TuistCoreTesting
import TuistGenerator
import TuistGraph
import TuistGraphTesting
import TuistSupport
import XCTest

@testable import TuistCore
@testable import TuistKit
@testable import TuistSigning
@testable import TuistSupportTesting

final class UpdateWorkspaceProjectsGraphMapperTests: TuistUnitTestCase {
    var subject: UpdateWorkspaceProjectsGraphMapper!

    override func setUp() {
        super.setUp()
        subject = UpdateWorkspaceProjectsGraphMapper()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_map_removesNonExistingProjects() throws {
        // Given
        let firstProjectPath: AbsolutePath = "/first-project"
        let secondProjectPath: AbsolutePath = "/second-project"
        let secondProject = Project.test(path: secondProjectPath)
        let workspace = Workspace.test(projects: [firstProjectPath, secondProjectPath])
        let graph = Graph.test(
            workspace: workspace,
            projects: [
                secondProject.path: secondProject,
            ]
        )

        // When
        let (gotGraph, gotSideEffects) = try subject.map(graph: graph)

        // Then
        XCTAssertEmpty(gotSideEffects)
        XCTAssertEqual(gotGraph.workspace.projects, [secondProjectPath])
    }
}
