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
        let got = subject.locate(at: stencilDirectory.appending(try RelativePath(validating: "this/is/a/very/nested/directory")))

        // Then
        XCTAssertEqual(got, stencilDirectory.appending(try RelativePath(validating: "this/is/Tuist/Stencils")))
    }

    func test_locate_when_a_stencil_directory_exists() throws {
        // Given
        let stencilDirectory = try temporaryPath()
        try createFolders(["this/is/a/very/nested/directory", "this/is/Tuist/Stencils"])

        // When
        let got = subject.locate(at: stencilDirectory.appending(try RelativePath(validating: "this/is/a/very/nested/directory")))

        // Then
        XCTAssertEqual(got, stencilDirectory.appending(try RelativePath(validating: "this/is/Tuist/Stencils")))
    }

    func test_locate_when_a_git_directory_exists() throws {
        // Given
        let stencilDirectory = try temporaryPath()
        try createFolders(["this/is/a/very/nested/directory", "this/.git", "this/Tuist/Stencils"])

        // When
        let got = subject.locate(at: stencilDirectory.appending(try RelativePath(validating: "this/is/a/very/nested/directory")))

        // Then
        XCTAssertEqual(got, stencilDirectory.appending(try RelativePath(validating: "this/Tuist/Stencils")))
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
        let got = try paths.map {
            subject.locate(at: stencilDirectory.appending(try RelativePath(validating: $0)))
        }

        // Then
        XCTAssertEqual(got, try [
            "this/is/Tuist/Stencils",
            "this/is/a/very/nested/Tuist/Stencils",
        ].map { stencilDirectory.appending(try RelativePath(validating: $0)) })
    }
}
