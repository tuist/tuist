import FileSystem
import FileSystemTesting
import Foundation
import Path
import ProjectDescription
import Testing
import TuistCore
import TuistRootDirectoryLocator
import TuistTesting

@testable import TuistLoader

struct StencilManifestMapperTests {
    private let subject: StencilPathLocator

    init() {
        subject = StencilPathLocator(rootDirectoryLocator: RootDirectoryLocator())
    }

    @Test(.inTemporaryDirectory) func locate_when_a_stencil_and_git_directory_exists() async throws {
        // Given
        let stencilDirectory = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.createFolders(["this/is/a/very/nested/directory", "this/is/Tuist/Stencils", "this/.git"])

        // When
        let got = try await subject
            .locate(at: stencilDirectory.appending(try RelativePath(validating: "this/is/a/very/nested/directory")))

        // Then
        #expect(got == stencilDirectory.appending(try RelativePath(validating: "this/is/Tuist/Stencils")))
    }

    @Test(.inTemporaryDirectory) func locate_when_a_stencil_directory_exists() async throws {
        // Given
        let stencilDirectory = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.createFolders(["this/is/a/very/nested/directory", "this/is/Tuist/Stencils"])

        // When
        let got = try await subject
            .locate(at: stencilDirectory.appending(try RelativePath(validating: "this/is/a/very/nested/directory")))

        // Then
        #expect(got == stencilDirectory.appending(try RelativePath(validating: "this/is/Tuist/Stencils")))
    }

    @Test(.inTemporaryDirectory) func locate_when_a_git_directory_exists() async throws {
        // Given
        let stencilDirectory = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.createFolders(["this/is/a/very/nested/directory", "this/.git", "this/Tuist/Stencils"])

        // When
        let got = try await subject
            .locate(at: stencilDirectory.appending(try RelativePath(validating: "this/is/a/very/nested/directory")))

        // Then
        #expect(got == stencilDirectory.appending(try RelativePath(validating: "this/Tuist/Stencils")))
    }

    @Test(.inTemporaryDirectory) func locate_when_multiple_tuist_directories_exists() async throws {
        // Given
        let stencilDirectory = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.createFolders(["this/is/a/very/nested/Tuist/Stencils", "this/is/Tuist/Stencils"])
        let paths = [
            "this/is/a/very/directory",
            "this/is/a/very/nested/directory",
        ]

        // When
        let got = try await paths.concurrentMap {
            try await self.subject.locate(at: stencilDirectory.appending(try RelativePath(validating: $0)))
        }

        // Then
        #expect(got == (try [
            "this/is/Tuist/Stencils",
            "this/is/a/very/nested/Tuist/Stencils",
        ].map { stencilDirectory.appending(try RelativePath(validating: $0)) }))
    }
}
