import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistConstants
import TuistCore
import TuistSupport
import TuistTesting

@testable import TuistRootDirectoryLocator

struct RootDirectoryLocatorTests {
    let subject: RootDirectoryLocator
    init() {
        subject = RootDirectoryLocator()
    }

    @Test(.inTemporaryDirectory)
    func locate_when_a_tuist_and_git_directory_exists() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.makeDirectories(["this/is/a/very/nested/directory", "this/is/Tuist/", "this/.git"])

        // When
        let got = try await subject
            .locate(from: temporaryDirectory.appending(try RelativePath(validating: "this/is/a/very/nested/directory")))

        // Then
        #expect(got == temporaryDirectory.appending(try RelativePath(validating: "this/is")))
    }

    @Test(.inTemporaryDirectory)
    func locate_when_a_tuist_directory_exists() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.makeDirectories(["this/is/a/very/nested/directory", "this/is/Tuist/"])

        // When
        let got = try await subject
            .locate(from: temporaryDirectory.appending(try RelativePath(validating: "this/is/a/very/nested/directory")))

        // Then
        #expect(got == temporaryDirectory.appending(try RelativePath(validating: "this/is")))
    }

    @Test(.inTemporaryDirectory)
    func locate_when_a_tuist_swift_manifest_file_exists() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.makeDirectories(["this/is/a/very/nested/directory"])
        try await TuistTest.createFiles(["this/is/\(Constants.tuistManifestFileName)"])

        // When
        let got = try await subject
            .locate(from: temporaryDirectory.appending(try RelativePath(validating: "this/is/a/very/nested/directory")))

        // Then
        #expect(got == temporaryDirectory.appending(try RelativePath(validating: "this/is")))
    }

    @Test(.inTemporaryDirectory)
    func locate_when_a_tuist_toml_file_exists() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.makeDirectories(["this/is/a/very/nested/directory"])
        try await TuistTest.createFiles(["this/is/\(Constants.tuistTomlFileName)"])

        // When
        let got = try await subject
            .locate(from: temporaryDirectory.appending(try RelativePath(validating: "this/is/a/very/nested/directory")))

        // Then
        #expect(got == temporaryDirectory.appending(try RelativePath(validating: "this/is")))
    }

    @Test(.inTemporaryDirectory)
    func locate_when_a_git_directory_exists() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.makeDirectories(["this/is/a/very/nested/directory", "this/.git"])

        // When
        let got = try await subject
            .locate(from: temporaryDirectory.appending(try RelativePath(validating: "this/is/a/very/nested/directory")))

        // Then
        #expect(got == temporaryDirectory.appending(try RelativePath(validating: "this")))
    }

    @Test(.inTemporaryDirectory)
    func locate_when_a_tuist_file_is_present_not_directory() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.makeDirectories(["this/is/a/directory"])
        try await TuistTest.createFiles(["this/is/a/directory/tuist"])

        // When
        let got = try await subject
            .locate(from: temporaryDirectory.appending(try RelativePath(validating: "this/is/a/directory")))

        // Then
        #expect(got == nil)
    }

    @Test(.inTemporaryDirectory)
    func locate_when_multiple_tuist_directories_exists() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.makeDirectories(["this/is/a/very/nested/Tuist/", "this/is/Tuist/"])
        let paths = [
            "this/is/a/very/directory",
            "this/is/a/very/nested/directory",
        ]

        // When
        let got = try await paths.concurrentMap {
            try await subject.locate(from: temporaryDirectory.appending(try RelativePath(validating: $0)))
        }

        // Then
        let expected = try [
            "this/is",
            "this/is/a/very/nested",
        ].map { temporaryDirectory.appending(try RelativePath(validating: $0)) }
        #expect(got == expected)
    }

    @Test(.inTemporaryDirectory)
    func locate_when_only_plugin_manifest_exists() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.createFiles([
            "Plugin.swift",
        ])

        // When
        let got = try await subject.locate(from: temporaryDirectory.appending(component: "Plugin.swift"))

        // Then
        #expect(got == temporaryDirectory)
    }

    @Test(.inTemporaryDirectory)
    func locate_when_a_tuist_directory_and_plugin_exists() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.createFiles([
            "APlugin/Plugin.swift",
            "Tuist/",
        ])
        let paths = [
            "APlugin/",
            "APlugin/Plugin.swift",
        ]

        // When
        let got = try await paths.concurrentMap {
            try await subject.locate(from: temporaryDirectory.appending(try RelativePath(validating: $0)))
        }

        // Then
        let expected = try [
            "APlugin/",
            "APlugin/",
        ].map { temporaryDirectory.appending(try RelativePath(validating: $0)) }
        #expect(got == expected)
    }

    @Test(.inTemporaryDirectory)
    func locate_when_a_git_directory_and_plugin_exists() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.createFiles([
            "APlugin/Plugin.swift",
            ".git/",
        ])
        let paths = [
            "APlugin/",
            "APlugin/Plugin.swift",
        ]

        // When
        let got = try await paths.concurrentMap {
            try await subject.locate(from: temporaryDirectory.appending(try RelativePath(validating: $0)))
        }

        // Then
        let expected = try [
            "APlugin/",
            "APlugin/",
        ].map { temporaryDirectory.appending(try RelativePath(validating: $0)) }
        #expect(got == expected)
    }

    @Test(.inTemporaryDirectory)
    func locate_when_a_swiftpm_manifest_file_exists() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.createFiles(["SomePackage/\(Constants.SwiftPackageManager.packageSwiftName)"])

        // When
        let got = try await subject
            .locate(from: temporaryDirectory.appending(try RelativePath(validating: "SomePackage")))

        // Then
        #expect(got == temporaryDirectory.appending(try RelativePath(validating: "SomePackage")))
    }

    @Test(.inTemporaryDirectory)
    func locate_when_a_tuist_directory_and_swiftpm_manifest_exists() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.makeDirectories([
            "this/is/a/very/nested/directory/\(Constants.SwiftPackageManager.packageSwiftName)",
            "this/is/Tuist/",
        ])

        // When
        let got = try await subject
            .locate(from: temporaryDirectory.appending(try RelativePath(validating: "this/is/a/very/nested/directory")))

        // Then
        #expect(got == temporaryDirectory.appending(try RelativePath(validating: "this/is")))
    }
}
