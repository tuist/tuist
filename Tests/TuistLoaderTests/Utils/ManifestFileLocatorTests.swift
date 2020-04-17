import Basic
import Foundation
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting
@testable import TuistCoreTesting

final class ManifestFileLocatorTests: TuistUnitTestCase {
    
    func test_locateAll_returns_all_manifest_no_workspace_given_child_path() throws {
        // Given
        let paths = try createFiles([
            "Module/Project.swift",
            "Project.swift",
            "Tuist/Config.swift"
        ])
        let subject = ManifestFilesLocator()

        // When
        let manifests = subject.locateAll(at: paths.first!)

        // Then
        XCTAssertEqual(manifests.count, 2)
        XCTAssertEqual(manifests.first?.0, Manifest.project)
        XCTAssertEqual(manifests.first?.1, paths.first)
        XCTAssertEqual(manifests.last?.0, Manifest.project)
        XCTAssertEqual(manifests.last?.1, paths.dropLast().last)
    }
    
    func test_locateAll_returns_all_manifest_with_workspace_given_child_path() throws {
        // Given
        let paths = try createFiles([
            "Module/Project.swift",
            "Workspace.swift",
            "Tuist/Config.swift"
        ])

        let subject = ManifestFilesLocator()

        // When
        let manifests = subject.locateAll(at: paths.first!)

        // Then
        XCTAssertEqual(manifests.first?.0, Manifest.project)
        XCTAssertEqual(manifests.first?.1, paths.first)
        XCTAssertEqual(manifests.last?.0, Manifest.workspace)
        XCTAssertEqual(manifests.last?.1, paths.dropLast().last)
    }
    
}
