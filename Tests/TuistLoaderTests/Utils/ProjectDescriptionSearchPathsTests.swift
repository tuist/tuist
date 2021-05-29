import Foundation
import TSCBasic
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class ProjectDescriptionSearchPathsTests: TuistUnitTestCase {
    func test_paths_style() throws {
        // Given
        let libraryPaths: [AbsolutePath] = [
            "/path/to/tuist/.build/debug/libProjectDescription.dylib",
            "/path/to/DerivedData/Debug/ProjectDescription.framework",
            "/path/to/DerivedData/Debug/PackageFrameworks/ProjectDescription.framework",
        ]

        // When
        let searchPaths = libraryPaths.map { ProjectDescriptionSearchPaths.paths(for: $0) }

        // Then
        XCTAssertEqual(searchPaths.map(\.style), [
            .commandLine,
            .xcode,
            .swiftPackageInXcode,
        ])
    }

    func test_paths_includeSearchPath() throws {
        // Given
        let libraryPaths: [AbsolutePath] = [
            "/path/to/tuist/.build/debug/libProjectDescription.dylib",
            "/path/to/DerivedData/Debug/ProjectDescription.framework",
            "/path/to/DerivedData/Debug/PackageFrameworks/ProjectDescription.framework",
        ]

        // When
        let searchPaths = libraryPaths.map { ProjectDescriptionSearchPaths.paths(for: $0) }

        // Then
        XCTAssertEqual(searchPaths.map(\.includeSearchPath), [
            "/path/to/tuist/.build/debug",
            "/path/to/DerivedData/Debug",
            "/path/to/DerivedData/Debug",
        ])
    }

    func test_paths_librarySearchPath() throws {
        // Given
        let libraryPaths: [AbsolutePath] = [
            "/path/to/tuist/.build/debug/libProjectDescription.dylib",
            "/path/to/DerivedData/Debug/ProjectDescription.framework",
            "/path/to/DerivedData/Debug/PackageFrameworks/ProjectDescription.framework",
        ]

        // When
        let searchPaths = libraryPaths.map { ProjectDescriptionSearchPaths.paths(for: $0) }

        // Then
        XCTAssertEqual(searchPaths.map(\.librarySearchPath), [
            "/path/to/tuist/.build/debug",
            "/path/to/DerivedData/Debug",
            "/path/to/DerivedData/Debug",
        ])
    }

    func test_paths_frameworkSearchPath() throws {
        // Given
        let libraryPaths: [AbsolutePath] = [
            "/path/to/tuist/.build/debug/libProjectDescription.dylib",
            "/path/to/DerivedData/Debug/ProjectDescription.framework",
            "/path/to/DerivedData/Debug/PackageFrameworks/ProjectDescription.framework",
        ]

        // When
        let searchPaths = libraryPaths.map { ProjectDescriptionSearchPaths.paths(for: $0) }

        // Then
        XCTAssertEqual(searchPaths.map(\.frameworkSearchPath), [
            "/path/to/tuist/.build/debug",
            "/path/to/DerivedData/Debug",
            "/path/to/DerivedData/Debug/PackageFrameworks",
        ])
    }
}
