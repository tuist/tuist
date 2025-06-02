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
        try fileHandler.createFolder(workspacePath.appending(components: ".build", "checkouts"))

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
}
