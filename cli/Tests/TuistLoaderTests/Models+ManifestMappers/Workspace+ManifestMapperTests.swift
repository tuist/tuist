import Foundation
import Mockable
import TuistCore
import TuistLoader
import TuistRootDirectoryLocator
import TuistTesting
import XcodeGraph
import XCTest

@testable import TuistLoader

final class WorkspaceManifestMapperTests: TuistUnitTestCase {
    private var manifestLoader: MockManifestLoading!
    private var rootDirectoryLocator: MockRootDirectoryLocating!

    override func setUp() {
        super.setUp()

        manifestLoader = .init()
        rootDirectoryLocator = .init()
    }

    override func tearDown() {
        manifestLoader = nil
        rootDirectoryLocator = nil
        super.tearDown()
    }

    func test_from_when_using_glob_for_projects() async throws {
        // Given
        given(manifestLoader)
            .manifests(at: .any)
            .willReturn([.project])

        let workspacePath = try temporaryPath()

        given(rootDirectoryLocator)
            .locate(from: .any)
            .willReturn(workspacePath)

        try await fileSystem.touch(workspacePath.appending(component: "Project.swift"))
        try await fileSystem.makeDirectory(at: workspacePath.appending(components: ".build", "checkouts"))

        // When
        let got = try await XcodeGraph.Workspace.from(
            manifest: .test(
                projects: [
                    "**",
                ]
            ),
            path: workspacePath,
            generatorPaths: .init(
                manifestDirectory: workspacePath,
                rootDirectory: workspacePath
            ),
            manifestLoader: manifestLoader,
            fileSystem: fileSystem
        )

        // Then
        XCTAssertBetterEqual(
            got,
            XcodeGraph.Workspace(
                path: workspacePath,
                xcWorkspacePath: workspacePath.appending(component: "Workspace.xcworkspace"),
                name: "Workspace",
                projects: [
                    workspacePath,
                ]
            )
        )
    }

    func test_from_when_workspacePathContainsCheckouts_doesNotFilterItOut() async throws {
        // Given
        given(manifestLoader)
            .manifests(at: .any)
            .willReturn([.project])

        let rootPath = try temporaryPath()
        let workspacePath = rootPath.appending(components: "checkouts", "App")
        let scratchDirectory = rootPath.appending(component: "custom-build")

        try await fileSystem.makeDirectory(at: workspacePath)
        try await fileSystem.makeDirectory(at: scratchDirectory.appending(component: "checkouts"))
        try await fileSystem.touch(workspacePath.appending(component: "Project.swift"))

        // When
        let got = try await XcodeGraph.Workspace.from(
            manifest: .test(
                projects: [
                    "**",
                ]
            ),
            path: workspacePath,
            generatorPaths: .init(
                manifestDirectory: workspacePath,
                rootDirectory: rootPath
            ),
            manifestLoader: manifestLoader,
            fileSystem: fileSystem,
            swiftPackageManagerScratchDirectory: scratchDirectory
        )

        // Then
        XCTAssertEqual(got.projects, [workspacePath])
    }

    func test_from_when_usingCustomSwiftPMScratchDirectory_ignoresPackagesInCheckouts() async throws {
        // Given
        given(manifestLoader)
            .manifests(at: .any)
            .willReturn([.project])

        let workspacePath = try temporaryPath()
        let scratchDirectory = workspacePath.appending(component: "custom-build")
        let checkoutPath = scratchDirectory.appending(components: "checkouts", "Dependency")

        try await fileSystem.touch(workspacePath.appending(component: "Project.swift"))
        try await fileSystem.makeDirectory(at: checkoutPath)
        try await fileSystem.touch(checkoutPath.appending(component: "Package.swift"))

        // When
        let got = try await XcodeGraph.Workspace.from(
            manifest: .test(
                projects: [
                    "**",
                ]
            ),
            path: workspacePath,
            generatorPaths: .init(
                manifestDirectory: workspacePath,
                rootDirectory: workspacePath
            ),
            manifestLoader: manifestLoader,
            fileSystem: fileSystem,
            swiftPackageManagerScratchDirectory: scratchDirectory
        )

        // Then
        XCTAssertEqual(got.projects, [workspacePath])
    }
}
