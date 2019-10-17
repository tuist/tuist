import Basic
import Foundation
import TuistCore
import XCTest

@testable import TuistCoreTesting
@testable import TuistGenerator

final class ProjectFilesSortenerTests: TuistUnitTestCase {
    var subject: ProjectFilesSortener!

    override func setUp() {
        super.setUp()
        subject = ProjectFilesSortener()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_sort() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let basePath = temporaryPath
        let file1 = basePath.appending(RelativePath("path/to/sources/file.swift"))
        let file2 = basePath.appending(RelativePath("path/to/tests/test.swift"))
        let file3 = basePath.appending(RelativePath("path/to/tuist.swift"))
        let file4 = basePath.appending(RelativePath("path/to/waka.swift"))
        let files = [file1, file2, file3, file4]
        try files.forEach { try FileHandler.shared.touch($0) }

        // When
        let got = files.sorted(by: subject.sort)

        // Then
        XCTAssertEqual(got[0], file3)
        XCTAssertEqual(got[1], file4)
        XCTAssertEqual(got[2], file1)
        XCTAssertEqual(got[3], file2)
    }

    func test_sort_isStable() throws {
        // Given
        let folders = try createFolders([
            "Root/A",
            "Root/A/A1",
            "Root/B",
            "Root/B/B1",
        ])

        let files = try createFiles([
            "Root/A/a.md",
            "Root/A/z.md",
            "Root/A/A1/a.md",
            "Root/A/A1/z.md",
            "Root/B/b.md",
            "Root/B/z.md",
            "Root/B/B1/b.md",
            "Root/B/B1/z.md",
        ])

        let paths = (files + folders)

        // When
        let got = (0 ..< 10).map { _ in paths.shuffled().sorted(by: subject.sort) }

        // Then
        let unstable = got.dropFirst().filter { $0 != got.first }
        XCTAssertTrue(unstable.isEmpty)
    }

    func test_sort_filesBeforeDirectories() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let folders = try createFolders([
            "Root/A",
            "Root/A/A1",
            "Root/B",
            "Root/B/B1",
        ])

        let files = try createFiles([
            "Root/A/a.md",
            "Root/A/z.md",
            "Root/A/A1/a.md",
            "Root/A/A1/z.md",
            "Root/B/b.md",
            "Root/B/z.md",
            "Root/B/B1/b.md",
            "Root/B/B1/z.md",
        ])

        let paths = (files + folders).shuffled()

        // When
        let got = paths.sorted(by: subject.sort)

        // Then
        let raltivePaths = got.map { $0.relative(to: temporaryPath).pathString }
        XCTAssertEqual(raltivePaths, [
            "Root/A/a.md",
            "Root/A/z.md",
            "Root/A/A1/a.md",
            "Root/A/A1/z.md",
            "Root/A/A1",
            "Root/A",
            "Root/B/b.md",
            "Root/B/z.md",
            "Root/B/B1/b.md",
            "Root/B/B1/z.md",
            "Root/B/B1",
            "Root/B",
        ])
    }
}
