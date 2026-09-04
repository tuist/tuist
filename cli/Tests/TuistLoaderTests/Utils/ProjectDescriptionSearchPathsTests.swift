import Foundation
import Path
import XCTest
@testable import TuistLoader
@testable import TuistTesting

final class ProjectDescriptionSearchPathsTests: TuistUnitTestCase {
    func test_paths_style() {
        // Given
        let libraryPaths: [AbsolutePath] = [
            "/path/to/tuist/.build/debug/libProjectDescription.dylib",
            "/path/to/tuist/.build/debug/libProjectDescription.so",
            "/path/to/DerivedData/Debug/ProjectDescription.framework",
            "/path/to/DerivedData/Debug/PackageFrameworks/ProjectDescription.framework",
        ]

        // When
        let searchPaths = libraryPaths.map { ProjectDescriptionSearchPaths.paths(for: $0) }

        // Then
        XCTAssertEqual(searchPaths.map(\.style), [
            .commandLine,
            .commandLine,
            .xcode,
            .swiftPackageInXcode,
        ])
    }

    func test_paths_includeSearchPath() {
        // Given
        let libraryPaths: [AbsolutePath] = [
            "/path/to/tuist/.build/debug/libProjectDescription.dylib",
            "/path/to/tuist/.build/debug/libProjectDescription.so",
            "/path/to/DerivedData/Debug/ProjectDescription.framework",
            "/path/to/DerivedData/Debug/PackageFrameworks/ProjectDescription.framework",
        ]

        // When
        let searchPaths = libraryPaths.map { ProjectDescriptionSearchPaths.paths(for: $0) }

        // Then
        XCTAssertEqual(searchPaths.map(\.includeSearchPath), [
            "/path/to/tuist/.build/debug/Modules",
            "/path/to/tuist/.build/debug/Modules",
            "/path/to/DerivedData/Debug",
            "/path/to/DerivedData/Debug",
        ])
    }

    func test_paths_librarySearchPath() {
        // Given
        let libraryPaths: [AbsolutePath] = [
            "/path/to/tuist/.build/debug/libProjectDescription.dylib",
            "/path/to/tuist/.build/debug/libProjectDescription.so",
            "/path/to/DerivedData/Debug/ProjectDescription.framework",
            "/path/to/DerivedData/Debug/PackageFrameworks/ProjectDescription.framework",
        ]

        // When
        let searchPaths = libraryPaths.map { ProjectDescriptionSearchPaths.paths(for: $0) }

        // Then
        XCTAssertEqual(searchPaths.map(\.librarySearchPath), [
            "/path/to/tuist/.build/debug",
            "/path/to/tuist/.build/debug",
            "/path/to/DerivedData/Debug",
            "/path/to/DerivedData/Debug",
        ])
    }

    func test_paths_frameworkSearchPath() {
        // Given
        let libraryPaths: [AbsolutePath] = [
            "/path/to/tuist/.build/debug/libProjectDescription.dylib",
            "/path/to/tuist/.build/debug/libProjectDescription.so",
            "/path/to/DerivedData/Debug/ProjectDescription.framework",
            "/path/to/DerivedData/Debug/PackageFrameworks/ProjectDescription.framework",
        ]

        // When
        let searchPaths = libraryPaths.map { ProjectDescriptionSearchPaths.paths(for: $0) }

        // Then
        XCTAssertEqual(searchPaths.map(\.frameworkSearchPath), [
            "/path/to/tuist/.build/debug",
            "/path/to/tuist/.build/debug",
            "/path/to/DerivedData/Debug",
            "/path/to/DerivedData/Debug/PackageFrameworks",
        ])
    }
}
