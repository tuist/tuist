import FileSystem
import FileSystemTesting
import Testing
import TuistCore
import TuistGenerator
import XcodeGraph

@testable import TuistTesting

struct LastUpgradeVersionWorkspaceMapperTests {
    let subject: LastUpgradeVersionWorkspaceMapper
    init() {
        subject = LastUpgradeVersionWorkspaceMapper()
    }

    @Test(.inTemporaryDirectory)
    func maps_last_upgrade_version() throws {
        // Given

        let workspace = Workspace.test(
            generationOptions: .test(
                lastXcodeUpgradeCheck: .init(12, 5, 1)
            )
        )
        let projectAPath = try #require(FileSystem.temporaryTestDirectory).appending(component: "A")
        let projectBPath = try #require(FileSystem.temporaryTestDirectory).appending(component: "B")

        let projectA = Project.test(
            path: projectAPath,
            name: "A",
            targets: [
                .test(),
            ],
            lastUpgradeCheck: nil
        )

        let projectB = Project.test(
            path: projectBPath,
            name: "B",
            targets: [
                .test(),
            ],
            lastUpgradeCheck: nil
        )

        // When
        let (gotWorkspaceWithProjects, gotSideEffects) = try subject.map(
            workspace: WorkspaceWithProjects(
                workspace: workspace,
                projects: [
                    projectA,
                    projectB,
                ]
            )
        )

        // Then
        let mappedProjectA = Project.test(
            path: projectAPath,
            name: "A",
            targets: [
                .test(),
            ],
            lastUpgradeCheck: .init(12, 5, 1)
        )

        let mappedProjectB = Project.test(
            path: projectBPath,
            name: "B",
            targets: [
                .test(),
            ],
            lastUpgradeCheck: .init(12, 5, 1)
        )

        #expect(gotWorkspaceWithProjects == WorkspaceWithProjects(
            workspace: workspace,
            projects: [
                mappedProjectA,
                mappedProjectB,
            ]
        ))
        #expect(gotSideEffects == [])
    }
}
