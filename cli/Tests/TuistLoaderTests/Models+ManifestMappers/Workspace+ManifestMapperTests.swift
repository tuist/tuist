import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Testing
import TuistCore
import TuistLoader
import TuistRootDirectoryLocator
import TuistTesting
import XcodeGraph

@testable import TuistLoader

struct WorkspaceManifestMapperTests {
    private let manifestLoader: MockManifestLoading
    private let rootDirectoryLocator: MockRootDirectoryLocating
    private let fileSystem = FileSystem()

    init() {
        manifestLoader = .init()
        rootDirectoryLocator = .init()
    }

    @Test(.inTemporaryDirectory) func from_when_using_glob_for_projects() async throws {
        // Given
        given(manifestLoader)
            .manifests(at: .any)
            .willReturn([.project])

        let workspacePath = try #require(FileSystem.temporaryTestDirectory)

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
        #expect(
            got ==
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
