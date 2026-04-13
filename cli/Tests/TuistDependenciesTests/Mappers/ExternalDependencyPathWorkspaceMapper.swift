import FileSystem
import Foundation
import TuistConstants
import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph
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

    func test_map() async throws {
        // Given
        let projectPath = try temporaryPath()
        let project = Project.test(
            path: projectPath,
            sourceRootPath: projectPath,
            xcodeProjPath: projectPath.appending(component: "A.xcodeproj"),
            name: "A"
        )

        let externalProjectBasePath = try temporaryPath()
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
        let (gotWorkspaceWithProjects, _) = try await subject.map(
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
                Constants.DerivedDirectory.dependenciesProjectDirectory,
                "ExternalDependency",
                "ExternalDependency.xcodeproj",
            ]
        )
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
            ]
        )
    }

    func test_map_removesStaleDirectoryWithMismatchedCasing() async throws {
        // Given: A tuist-derived directory exists with "SwiftyMocky" casing (e.g., from a previous run)
        // but the project name uses "swiftymocky" casing (from Package.swift)
        let externalProjectBasePath = try temporaryPath()
            .appending(component: Constants.SwiftPackageManager.packageBuildDirectoryName)

        let derivedDir = externalProjectBasePath.appending(
            components: [
                Constants.DerivedDirectory.dependenciesDerivedDirectory,
                Constants.DerivedDirectory.dependenciesProjectDirectory,
            ]
        )
        let oldCasingDir = derivedDir.appending(component: "SwiftyMocky")
        let fileSystem = FileSystem()
        try await fileSystem.makeDirectory(at: oldCasingDir)

        let externalProjectPath = externalProjectBasePath.appending(
            components: ["checkouts", "SwiftyMocky"]
        )
        let externalProject = Project.test(
            path: externalProjectPath,
            sourceRootPath: externalProjectPath,
            xcodeProjPath: externalProjectPath.appending(component: "swiftymocky.xcodeproj"),
            name: "swiftymocky",
            type: .external(hash: nil)
        )

        // When
        let (gotWorkspaceWithProjects, _) = try await subject.map(
            workspace: WorkspaceWithProjects(
                workspace: .test(name: "A"),
                projects: [externalProject]
            )
        )

        // Then: The stale directory should be removed so XcodeProj.write recreates it with correct casing
        let entries = try await fileSystem.glob(directory: derivedDir, include: ["*"]).collect().map(\.basename)
        XCTAssertFalse(entries.contains("SwiftyMocky"), "Stale directory 'SwiftyMocky' should have been removed")

        // The xcodeproj path should use the lowercase name
        XCTAssertEqual(
            gotWorkspaceWithProjects.projects.first?.xcodeProjPath,
            externalProjectBasePath.appending(
                components: [
                    Constants.DerivedDirectory.dependenciesDerivedDirectory,
                    Constants.DerivedDirectory.dependenciesProjectDirectory,
                    "swiftymocky",
                    "swiftymocky.xcodeproj",
                ]
            )
        )
    }

    func test_map_namespacesExternalProjectsToAvoidCollidingWithTargetDerivedDirectories() async throws {
        // Given
        let externalProjectBasePath = try temporaryPath()
            .appending(component: Constants.SwiftPackageManager.packageBuildDirectoryName)
        let externalProjectPath = externalProjectBasePath.appending(
            components: [
                "checkouts",
                "vgsl",
            ]
        )
        let externalProject = Project.test(
            path: externalProjectPath,
            sourceRootPath: externalProjectPath,
            xcodeProjPath: externalProjectPath.appending(component: "vgsl.xcodeproj"),
            name: "vgsl",
            type: .external(hash: nil)
        )

        // When
        let (gotWorkspaceWithProjects, _) = try await subject.map(
            workspace: WorkspaceWithProjects(
                workspace: .test(name: "A"),
                projects: [externalProject]
            )
        )

        // Then
        XCTAssertEqual(
            gotWorkspaceWithProjects.projects.first?.xcodeProjPath,
            externalProjectBasePath.appending(
                components: [
                    Constants.DerivedDirectory.dependenciesDerivedDirectory,
                    Constants.DerivedDirectory.dependenciesProjectDirectory,
                    "vgsl",
                    "vgsl.xcodeproj",
                ]
            )
        )
    }
}
