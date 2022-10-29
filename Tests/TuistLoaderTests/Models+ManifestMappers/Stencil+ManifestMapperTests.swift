import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistLoaderTesting
import TuistSupportTesting
import XCTest

@testable import TuistLoader

final class StencilManifestMapperTests: TuistUnitTestCase {
    private var subject: StencilPathLocator!

    override func setUp() {
        super.setUp()

        subject = StencilPathLocator(rootDirectoryLocator: RootDirectoryLocator())
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_locate_when_a_stencil_and_git_directory_exists() throws {
        // Given
        let stencilDirectory = try temporaryPath()
        try createFolders(["this/is/a/very/nested/directory", "this/is/Tuist/Stencils", "this/.git"])

        // When
        let got = subject.locate(at: stencilDirectory.appending(RelativePath("this/is/a/very/nested/directory")))

        // Then
        XCTAssertEqual(got, stencilDirectory.appending(RelativePath("this/is/Tuist/Stencils")))
    }

    func test_locate_when_a_stencil_directory_exists() throws {
        // Given
        let stencilDirectory = try temporaryPath()
        try createFolders(["this/is/a/very/nested/directory", "this/is/Tuist/Stencils"])

        // When
        let got = subject.locate(at: stencilDirectory.appending(RelativePath("this/is/a/very/nested/directory")))

        // Then
        XCTAssertEqual(got, stencilDirectory.appending(RelativePath("this/is/Tuist/Stencils")))
    }

    func test_locate_when_a_git_directory_exists() throws {
        // Given
        let stencilDirectory = try temporaryPath()
        try createFolders(["this/is/a/very/nested/directory", "this/.git", "this/Tuist/Stencils"])

        // When
        let got = subject.locate(at: stencilDirectory.appending(RelativePath("this/is/a/very/nested/directory")))

        // Then
        XCTAssertEqual(got, stencilDirectory.appending(RelativePath("this/Tuist/Stencils")))
    }

    func test_locate_when_multiple_tuist_directories_exists() throws {
        // Given
        let stencilDirectory = try temporaryPath()
        try createFolders(["this/is/a/very/nested/Tuist/Stencils", "this/is/Tuist/Stencils"])
        let paths = [
            "this/is/a/very/directory",
            "this/is/a/very/nested/directory",
        ]

        // When
        let got = paths.map {
            subject.locate(at: stencilDirectory.appending(RelativePath($0)))
        }

        // Then
        XCTAssertEqual(got, [
            "this/is/Tuist/Stencils",
            "this/is/a/very/nested/Tuist/Stencils",
        ].map { stencilDirectory.appending(RelativePath($0)) })
    }
}
