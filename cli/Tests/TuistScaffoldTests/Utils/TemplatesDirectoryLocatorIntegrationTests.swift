import Foundation
import Path
import TuistRootDirectoryLocator
import TuistSupport
import FileSystemTesting
import Testing

@testable import TuistCore
@testable import TuistScaffold
@testable import TuistTesting

struct TemplatesDirectoryLocatorIntegrationTests {
    let subject: TemplatesDirectoryLocator
    init() {
        subject = TemplatesDirectoryLocator(rootDirectoryLocator: RootDirectoryLocator())
    }


    @Test(.inTemporaryDirectory)
    func test_locate_when_a_templates_and_git_directory_exists() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        try createFolders(["this/is/a/very/nested/directory", "this/is/Tuist/Templates", "this/.git"])

        // When
        let got = try await subject
            .locateUserTemplates(
                at: temporaryDirectory
                    .appending(try RelativePath(validating: "this/is/a/very/nested/directory"))
            )

        // Then
        #expect(got == temporaryDirectory.appending(try RelativePath(validating: "this/is/Tuist/Templates")))
    }

    @Test(.inTemporaryDirectory)
    func test_locate_when_a_templates_directory_exists() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        try createFolders(["this/is/a/very/nested/directory", "this/is/Tuist/Templates"])

        // When
        let got = try await subject
            .locateUserTemplates(
                at: temporaryDirectory
                    .appending(try RelativePath(validating: "this/is/a/very/nested/directory"))
            )

        // Then
        #expect(got == temporaryDirectory.appending(try RelativePath(validating: "this/is/Tuist/Templates")))
    }

    @Test(.inTemporaryDirectory)
    func test_locate_when_a_git_directory_exists() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        try createFolders(["this/is/a/very/nested/directory", "this/.git", "this/Tuist/Templates"])

        // When
        let got = try await subject
            .locateUserTemplates(
                at: temporaryDirectory
                    .appending(try RelativePath(validating: "this/is/a/very/nested/directory"))
            )

        // Then
        #expect(got == temporaryDirectory.appending(try RelativePath(validating: "this/Tuist/Templates")))
    }

    @Test(.inTemporaryDirectory)
    func test_locate_when_multiple_tuist_directories_exists() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        try createFolders(["this/is/a/very/nested/Tuist/Templates", "this/is/Tuist/Templates"])
        let paths = [
            "this/is/a/very/directory",
            "this/is/a/very/nested/directory",
        ]

        // When
        let got = try await paths.concurrentMap {
            try await self.subject.locateUserTemplates(
                at: temporaryDirectory.appending(try RelativePath(validating: $0))
            )
        }

        // Then
        #expect(got == try [
            "this/is/Tuist/Templates",
            "this/is/a/very/nested/Tuist/Templates",
        ].map { temporaryDirectory.appending(try RelativePath(validating: $0)) })
    }
}
