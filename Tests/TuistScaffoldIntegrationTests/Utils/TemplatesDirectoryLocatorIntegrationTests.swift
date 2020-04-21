import Foundation
import TSCBasic
import TuistSupport
import XCTest

@testable import TuistCore
@testable import TuistScaffold
@testable import TuistSupportTesting

final class TemplatesDirectoryLocatorIntegrationTests: TuistTestCase {
    var subject: TemplatesDirectoryLocator!

    override func setUp() {
        super.setUp()
        subject = TemplatesDirectoryLocator(rootDirectoryLocator: RootDirectoryLocator())
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_locate_when_a_templates_and_git_directory_exists() throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        try createFolders(["this/is/a/very/nested/directory", "this/is/Tuist/Templates", "this/.git"])

        // When
        let got = subject.locateUserTemplates(at: temporaryDirectory.appending(RelativePath("this/is/a/very/nested/directory")))

        // Then
        XCTAssertEqual(got, temporaryDirectory.appending(RelativePath("this/is/Tuist/Templates")))
    }

    func test_locate_when_a_templates_directory_exists() throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        try createFolders(["this/is/a/very/nested/directory", "this/is/Tuist/Templates"])

        // When
        let got = subject.locateUserTemplates(at: temporaryDirectory.appending(RelativePath("this/is/a/very/nested/directory")))

        // Then
        XCTAssertEqual(got, temporaryDirectory.appending(RelativePath("this/is/Tuist/Templates")))
    }

    func test_locate_when_a_git_directory_exists() throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        try createFolders(["this/is/a/very/nested/directory", "this/.git", "this/Tuist/Templates"])

        // When
        let got = subject.locateUserTemplates(at: temporaryDirectory.appending(RelativePath("this/is/a/very/nested/directory")))

        // Then
        XCTAssertEqual(got, temporaryDirectory.appending(RelativePath("this/Tuist/Templates")))
    }

    func test_locate_when_multiple_tuist_directories_exists() throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        try createFolders(["this/is/a/very/nested/Tuist/Templates", "this/is/Tuist/Templates"])
        let paths = [
            "this/is/a/very/directory",
            "this/is/a/very/nested/directory",
        ]

        // When
        let got = paths.map {
            subject.locateUserTemplates(at: temporaryDirectory.appending(RelativePath($0)))
        }

        // Then
        XCTAssertEqual(got, [
            "this/is/Tuist/Templates",
            "this/is/a/very/nested/Tuist/Templates",
        ].map { temporaryDirectory.appending(RelativePath($0)) })
    }
}
