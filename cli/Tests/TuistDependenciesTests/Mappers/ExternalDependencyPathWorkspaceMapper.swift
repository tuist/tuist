import FileSystemTesting
import Foundation
import Testing
import TuistConstants
import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph

@testable import TuistDependencies

struct ExternalDependencyPathWorkspaceMapperTests {
    private let subject: ExternalDependencyPathWorkspaceMapper
    init() {
        subject = ExternalDependencyPathWorkspaceMapper()
    }

    @Test(.inTemporaryDirectory)
    func test_map() throws {
        // Given
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
        let project = Project.test(
            path: projectPath,
            sourceRootPath: projectPath,
            xcodeProjPath: projectPath.appending(component: "A.xcodeproj"),
            name: "A"
        )

        let externalProjectBasePath = try #require(FileSystem.temporaryTestDirectory)
            .appending(component: Constants.SwiftPackageManager.packageBuildDirectoryName)
        let externalProjectPath = externalProjectBasePath.appending(
            components: [
                "checkouts",
                "ExternalDependency",
            ]
        )
        let externalProject = Project.test(
            path: externalProjectPath,
            sourceRootPath: externalProjectPath,
            xcodeProjPath: externalProjectPath.appending(component: "ExternalDependency.xcodeproj"),
            name: "ExternalDependency",
            type: .external(hash: nil)
        )

        let workspace = Workspace.test(
            name: "A"
        )

        // When
        let (gotWorkspaceWithProjects, _) = try subject.map(
            workspace: WorkspaceWithProjects(
                workspace: workspace,
                projects: [
                    project,
                    externalProject,
                ]
            )
        )

        // Then
        let expectedXcodeprojPath = externalProjectBasePath.appending(
            components: [
                Constants.DerivedDirectory.dependenciesDerivedDirectory,
                "ExternalDependency",
                "ExternalDependency.xcodeproj",
            ]
        )
        #expect(gotWorkspaceWithProjects.projects == [
            Project.test(
                path: projectPath,
                sourceRootPath: projectPath,
                xcodeProjPath: projectPath.appending(component: "A.xcodeproj"),
                name: "A"
            ),
            Project.test(
                path: externalProjectPath,
                sourceRootPath: externalProject.sourceRootPath,
                xcodeProjPath: expectedXcodeprojPath,
                name: "ExternalDependency",
                settings: Settings.test(
                    base: [
                        "SRCROOT": .string(externalProject.sourceRootPath.relative(to: expectedXcodeprojPath.parentDirectory)
                            .pathString
                        ),
                    ]
                ),
                type: .external(hash: nil)
            ),
        ])
    }
}
