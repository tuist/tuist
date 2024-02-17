import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import TuistSupportTesting
import XCTest

@testable import TuistDependencies

final class ExternalDependencyPathWorkspaceMapperTests: TuistUnitTestCase {
    private var subject: ExternalDependencyPathWorkspaceMapper!

    override func setUp() {
        super.setUp()
        subject = ExternalDependencyPathWorkspaceMapper()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
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
        
        let externalProjectBasePath = try temporaryPath().appending(component: Constants.SwiftPackageManager.packageBuildDirectoryName)
        let externalProjectPath = externalProjectBasePath.appending(
            components: [
                "checkouts",
                "ExternalDependency"
            ]
        )
        let externalProject = Project.test(
            path: externalProjectPath,
            sourceRootPath: externalProjectPath,
            xcodeProjPath: externalProjectPath.appending(component: "ExternalDependency.xcodeproj"),
            name: "ExternalDependency",
            isExternal: true
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
        XCTAssertBetterEqual(
            gotWorkspaceWithProjects.projects,
            [
                Project.test(
                    path: projectPath,
                    sourceRootPath: projectPath,
                    xcodeProjPath: projectPath.appending(component: "A.xcodeproj"),
                    name: "A"
                ),
                Project.test(
                    path: externalProjectPath,
                    sourceRootPath: externalProject.sourceRootPath,
                    xcodeProjPath: externalProjectBasePath.appending(
                        components: [
                            Constants.DerivedDirectory.dependenciesDerivedDirectory,
                            "ExternalDependency",
                            "ExternalDependency.xcodeproj",
                        ]
                     ),
                    name: "ExternalDependency",
                    settings: Settings.test(
                        base: [
                            "SRCROOT": .string(externalProjectPath.pathString),
                        ]
                    ),
                    isExternal: true
                ),
            ]
        )
    }
}
