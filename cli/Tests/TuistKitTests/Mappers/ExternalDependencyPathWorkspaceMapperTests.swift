import TuistConstants
import TuistCore
import TuistDependencies
import TuistTesting
import XcodeGraph
import XCTest

final class ExternalDependencyPathWorkspaceMapperTests: TuistUnitTestCase {
    func test_map_whenExternalProjectUsesCustomScratchPath() throws {
        // Given
        let scratchDirectory = try temporaryPath().appending(component: "custom-build")
        let externalProjectPath = scratchDirectory.appending(
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
            type: .external(hash: nil),
            swiftPackageManagerScratchDirectory: scratchDirectory
        )

        // When
        let (gotWorkspaceWithProjects, _) = try ExternalDependencyPathWorkspaceMapper().map(
            workspace: WorkspaceWithProjects(
                workspace: .test(name: "A"),
                projects: [externalProject]
            )
        )

        // Then
        XCTAssertEqual(
            gotWorkspaceWithProjects.projects.first?.xcodeProjPath,
            scratchDirectory.appending(
                components: [
                    Constants.DerivedDirectory.dependenciesDerivedDirectory,
                    Constants.DerivedDirectory.dependenciesProjectDirectory,
                    "ExternalDependency",
                    "ExternalDependency.xcodeproj",
                ]
            )
        )
    }

    func test_map_whenExternalProjectPathContainsUnrelatedCheckoutsDirectory() throws {
        // Given
        let projectPath = try temporaryPath()
            .appending(components: "checkouts", "ExternalDependency")
        let externalProject = Project.test(
            path: projectPath,
            sourceRootPath: projectPath,
            xcodeProjPath: projectPath.appending(component: "ExternalDependency.xcodeproj"),
            name: "ExternalDependency",
            type: .external(hash: nil),
            swiftPackageManagerScratchDirectory: projectPath.parentDirectory.parentDirectory.appending(component: "custom-build")
        )

        // When
        let (gotWorkspaceWithProjects, _) = try ExternalDependencyPathWorkspaceMapper().map(
            workspace: WorkspaceWithProjects(
                workspace: .test(name: "A"),
                projects: [externalProject]
            )
        )

        // Then
        XCTAssertEqual(
            gotWorkspaceWithProjects.projects.first?.xcodeProjPath,
            projectPath.appending(component: "ExternalDependency.xcodeproj")
        )
    }
}
