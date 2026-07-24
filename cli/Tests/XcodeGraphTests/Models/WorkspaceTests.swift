import Foundation
import Path
import XCTest
@testable import XcodeGraph

final class WorkspaceTests: XCTestCase {
    func test_codable() throws {
        // Given
        let subject = Workspace.test(
            path: try AbsolutePath(validating: "/path/to/workspace"),
            name: "name"
        )

        // Then
        XCTAssertCodable(subject)
    }

    func test_replacingProjectsPreservesManifestProjectPaths() throws {
        // Given
        let projectAPath = try AbsolutePath(validating: "/A")
        let projectBPath = try AbsolutePath(validating: "/B")
        let projectCPath = try AbsolutePath(validating: "/C")
        let subject = Workspace.test(
            projects: [projectBPath, projectAPath],
            manifestProjectPaths: [projectBPath, projectAPath]
        )

        // When
        let replaced = subject.replacing(projects: [projectAPath, projectBPath, projectCPath])

        // Then
        XCTAssertEqual(replaced.projects, [projectAPath, projectBPath, projectCPath])
        XCTAssertEqual(replaced.manifestProjectPaths, [projectBPath, projectAPath])
    }
}
