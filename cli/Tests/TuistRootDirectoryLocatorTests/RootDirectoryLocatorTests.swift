import Foundation
import Path
import TuistCore
import TuistSupport
import TuistTesting
import XCTest

@testable import TuistRootDirectoryLocator

final class RootDirectoryLocatorTests: TuistTestCase {
    var subject: RootDirectoryLocator!

    override func setUp() {
        super.setUp()
        subject = RootDirectoryLocator()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_locate_when_a_tuist_and_git_directory_exists() async throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        try createFolders(["this/is/a/very/nested/directory", "this/is/Tuist/", "this/.git"])

        // When
        let got = try await subject
            .locate(from: temporaryDirectory.appending(try RelativePath(validating: "this/is/a/very/nested/directory")))

        // Then
        XCTAssertEqual(got, temporaryDirectory.appending(try RelativePath(validating: "this/is")))
    }

    func test_locate_when_a_tuist_directory_exists() async throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        try createFolders(["this/is/a/very/nested/directory", "this/is/Tuist/"])

        // When
        let got = try await subject
            .locate(from: temporaryDirectory.appending(try RelativePath(validating: "this/is/a/very/nested/directory")))

        // Then
        XCTAssertEqual(got, temporaryDirectory.appending(try RelativePath(validating: "this/is")))
    }

    func test_locate_when_a_tuist_swift_manifest_file_exists() async throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        try createFolders(["this/is/a/very/nested/directory"])
        try await createFiles(["this/is/\(Constants.tuistManifestFileName)"])

        // When
        let got = try await subject
            .locate(from: temporaryDirectory.appending(try RelativePath(validating: "this/is/a/very/nested/directory")))

        // Then
        XCTAssertEqual(got, temporaryDirectory.appending(try RelativePath(validating: "this/is")))
    }

    func test_locate_when_a_git_directory_exists() async throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        try createFolders(["this/is/a/very/nested/directory", "this/.git"])

        // When
        let got = try await subject
            .locate(from: temporaryDirectory.appending(try RelativePath(validating: "this/is/a/very/nested/directory")))

        // Then
        XCTAssertEqual(got, temporaryDirectory.appending(try RelativePath(validating: "this")))
    }

    func test_locate_when_a_tuist_file_is_present_not_directory() async throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        try createFolders(["this/is/a/directory"])
        try await createFiles(["this/is/a/directory/tuist"])

        // When
        let got = try await subject
            .locate(from: temporaryDirectory.appending(try RelativePath(validating: "this/is/a/directory")))

        // Then
        XCTAssertNil(got)
    }

    func test_locate_when_multiple_tuist_directories_exists() async throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        try createFolders(["this/is/a/very/nested/Tuist/", "this/is/Tuist/"])
        let paths = [
            "this/is/a/very/directory",
            "this/is/a/very/nested/directory",
        ]

        // When
        let got = try await paths.concurrentMap {
            try await self.subject.locate(from: temporaryDirectory.appending(try RelativePath(validating: $0)))
        }

        // Then
        XCTAssertEqual(got, try [
            "this/is",
            "this/is/a/very/nested",
        ].map { temporaryDirectory.appending(try RelativePath(validating: $0)) })
    }

    func test_locate_when_only_plugin_manifest_exists() async throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        try await createFiles([
            "Plugin.swift",
        ])

        // When
        let got = try await subject.locate(from: temporaryDirectory.appending(component: "Plugin.swift"))

        // Then
        XCTAssertEqual(got, temporaryDirectory)
    }

    func test_locate_when_a_tuist_directory_and_plugin_exists() async throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        try await createFiles([
            "APlugin/Plugin.swift",
            "Tuist/",
        ])
        let paths = [
            "APlugin/",
            "APlugin/Plugin.swift",
        ]

        // When
        let got = try await paths.concurrentMap {
            try await self.subject.locate(from: temporaryDirectory.appending(try RelativePath(validating: $0)))
        }

        // Then
        XCTAssertEqual(got, try [
            "APlugin/",
            "APlugin/",
        ].map { temporaryDirectory.appending(try RelativePath(validating: $0)) })
    }

    func test_locate_when_a_git_directory_and_plugin_exists() async throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        try await createFiles([
            "APlugin/Plugin.swift",
            ".git/",
        ])
        let paths = [
            "APlugin/",
            "APlugin/Plugin.swift",
        ]

        // When
        let got = try await paths.concurrentMap {
            try await self.subject.locate(from: temporaryDirectory.appending(try RelativePath(validating: $0)))
        }

        // Then
        XCTAssertEqual(got, try [
            "APlugin/",
            "APlugin/",
        ].map { temporaryDirectory.appending(try RelativePath(validating: $0)) })
    }

    func test_locate_when_a_swiftpm_manifest_file_exists() async throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        try await createFiles(["SomePackage/\(Constants.SwiftPackageManager.packageSwiftName)"])

        // When
        let got = try await subject
            .locate(from: temporaryDirectory.appending(try RelativePath(validating: "SomePackage")))

        // Then
        XCTAssertEqual(got, temporaryDirectory.appending(try RelativePath(validating: "SomePackage")))
    }

    func test_locate_when_a_tuist_directory_and_swiftpm_manifest_exists() async throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        try createFolders(["this/is/a/very/nested/directory/\(Constants.SwiftPackageManager.packageSwiftName)", "this/is/Tuist/"])

        // When
        let got = try await subject
            .locate(from: temporaryDirectory.appending(try RelativePath(validating: "this/is/a/very/nested/directory")))

        // Then
        XCTAssertEqual(got, temporaryDirectory.appending(try RelativePath(validating: "this/is")))
    }
}
