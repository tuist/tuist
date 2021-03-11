import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistSupportTesting

final class RootDirectoryLocatorIntegrationTests: TuistTestCase {
    var subject: RootDirectoryLocator!

    override func setUp() {
        super.setUp()
        subject = RootDirectoryLocator()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_locate_when_a_tuist_and_git_directory_exists() throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        try createFolders(["this/is/a/very/nested/directory", "this/is/Tuist/", "this/.git"])

        // When
        let got = subject.locate(from: temporaryDirectory.appending(RelativePath("this/is/a/very/nested/directory")))

        // Then
        XCTAssertEqual(got, temporaryDirectory.appending(RelativePath("this/is")))
    }

    func test_locate_when_a_tuist_directory_exists() throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        try createFolders(["this/is/a/very/nested/directory", "this/is/Tuist/"])

        // When
        let got = subject.locate(from: temporaryDirectory.appending(RelativePath("this/is/a/very/nested/directory")))

        // Then
        XCTAssertEqual(got, temporaryDirectory.appending(RelativePath("this/is")))
    }

    func test_locate_when_a_git_directory_exists() throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        try createFolders(["this/is/a/very/nested/directory", "this/.git"])

        // When
        let got = subject.locate(from: temporaryDirectory.appending(RelativePath("this/is/a/very/nested/directory")))

        // Then
        XCTAssertEqual(got, temporaryDirectory.appending(RelativePath("this")))
    }

    func test_locate_when_multiple_tuist_directories_exists() throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        try createFolders(["this/is/a/very/nested/Tuist/", "this/is/Tuist/"])
        let paths = [
            "this/is/a/very/directory",
            "this/is/a/very/nested/directory",
        ]

        // When
        let got = paths.map {
            subject.locate(from: temporaryDirectory.appending(RelativePath($0)))
        }

        // Then
        XCTAssertEqual(got, [
            "this/is",
            "this/is/a/very/nested",
        ].map { temporaryDirectory.appending(RelativePath($0)) })
    }

    func test_locate_when_only_plugin_manifest_exists() throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        try createFiles([
            "Plugin.swift",
        ])

        // When
        let got = subject.locate(from: temporaryDirectory.appending(component: "Plugin.swift"))

        // Then
        XCTAssertEqual(got, temporaryDirectory)
    }

    func test_locate_when_a_tuist_directory_and_plugin_exists() throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        try createFiles([
            "APlugin/Plugin.swift",
            "Tuist/",
        ])
        let paths = [
            "APlugin/",
            "APlugin/Plugin.swift",
        ]

        // When
        let got = paths.map {
            subject.locate(from: temporaryDirectory.appending(RelativePath($0)))
        }

        // Then
        XCTAssertEqual(got, [
            "APlugin/",
            "APlugin/",
        ].map { temporaryDirectory.appending(RelativePath($0)) })
    }

    func test_locate_when_a_git_directory_and_plugin_exists() throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        try createFiles([
            "APlugin/Plugin.swift",
            ".git/",
        ])
        let paths = [
            "APlugin/",
            "APlugin/Plugin.swift",
        ]

        // When
        let got = paths.map {
            subject.locate(from: temporaryDirectory.appending(RelativePath($0)))
        }

        // Then
        XCTAssertEqual(got, [
            "APlugin/",
            "APlugin/",
        ].map { temporaryDirectory.appending(RelativePath($0)) })
    }
}
