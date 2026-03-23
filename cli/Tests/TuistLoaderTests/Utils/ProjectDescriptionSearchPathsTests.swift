import Foundation
import Path
import Testing

@testable import TuistLoader
@testable import TuistTesting

struct ProjectDescriptionSearchPathsTests {
    @Test func paths_style() throws {
        // Given
        let libraryPaths: [AbsolutePath] = [
            "/path/to/tuist/.build/debug/libProjectDescription.dylib",
            "/path/to/DerivedData/Debug/ProjectDescription.framework",
            "/path/to/DerivedData/Debug/PackageFrameworks/ProjectDescription.framework",
        ]

        // When
        let searchPaths = libraryPaths.map { ProjectDescriptionSearchPaths.paths(for: $0) }

        // Then
        #expect(searchPaths.map(\.style) == [
            .commandLine,
            .xcode,
            .swiftPackageInXcode,
        ])
    }

    @Test func paths_includeSearchPath() throws {
        // Given
        let libraryPaths: [AbsolutePath] = [
            "/path/to/tuist/.build/debug/libProjectDescription.dylib",
            "/path/to/DerivedData/Debug/ProjectDescription.framework",
            "/path/to/DerivedData/Debug/PackageFrameworks/ProjectDescription.framework",
        ]

        // When
        let searchPaths = libraryPaths.map { ProjectDescriptionSearchPaths.paths(for: $0) }

        // Then
        #expect(searchPaths.map(\.includeSearchPath) == [
            "/path/to/tuist/.build/debug",
            "/path/to/DerivedData/Debug",
            "/path/to/DerivedData/Debug",
        ])
    }

    @Test func paths_librarySearchPath() throws {
        // Given
        let libraryPaths: [AbsolutePath] = [
            "/path/to/tuist/.build/debug/libProjectDescription.dylib",
            "/path/to/DerivedData/Debug/ProjectDescription.framework",
            "/path/to/DerivedData/Debug/PackageFrameworks/ProjectDescription.framework",
        ]

        // When
        let searchPaths = libraryPaths.map { ProjectDescriptionSearchPaths.paths(for: $0) }

        // Then
        #expect(searchPaths.map(\.librarySearchPath) == [
            "/path/to/tuist/.build/debug",
            "/path/to/DerivedData/Debug",
            "/path/to/DerivedData/Debug",
        ])
    }

    @Test func paths_frameworkSearchPath() throws {
        // Given
        let libraryPaths: [AbsolutePath] = [
            "/path/to/tuist/.build/debug/libProjectDescription.dylib",
            "/path/to/DerivedData/Debug/ProjectDescription.framework",
            "/path/to/DerivedData/Debug/PackageFrameworks/ProjectDescription.framework",
        ]

        // When
        let searchPaths = libraryPaths.map { ProjectDescriptionSearchPaths.paths(for: $0) }

        // Then
        #expect(searchPaths.map(\.frameworkSearchPath) == [
            "/path/to/tuist/.build/debug",
            "/path/to/DerivedData/Debug",
            "/path/to/DerivedData/Debug/PackageFrameworks",
        ])
    }
}
