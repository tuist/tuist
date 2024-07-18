import Foundation
import MockableTest
import TuistCore
import TuistLoader
import TuistSupportTesting
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

    func test_from_when_using_glob_for_projects() throws {
        // Given
        given(manifestLoader)
            .manifests(at: .any)
            .willReturn([.project])

        let workspacePath = try temporaryPath()

        given(rootDirectoryLocator)
            .locate(from: .any)
            .willReturn(workspacePath)

        try fileHandler.createFolder(workspacePath.appending(components: ".build", "checkouts"))

        // When
        let got = try XcodeGraph.Workspace.from(
            manifest: .test(
                projects: [
                    "**",
                ]
            ),
            path: workspacePath,
            generatorPaths: .init(
                manifestDirectory: workspacePath,
                rootDirectoryLocator: rootDirectoryLocator
            ),
            manifestLoader: manifestLoader
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
