import Foundation
import Path
import Testing
import TuistGenerator
import TuistSupport
import XcodeGraph

@testable import TuistCore
@testable import TuistKit
@testable import TuistTesting

@Suite(.withMockedDependencies()) struct UpdateWorkspaceProjectsGraphMapperTests {
    var subject: UpdateWorkspaceProjectsGraphMapper!

    init() {
        subject = UpdateWorkspaceProjectsGraphMapper()
    }

    @Test func map_removesNonExistingProjects() throws {
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
        let (gotGraph, gotSideEffects, _) = try subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        #expect(gotSideEffects.isEmpty)
        #expect(gotGraph.workspace.projects == [secondProjectPath])
    }
}
