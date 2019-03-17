import Basic
import Foundation
import TuistCore
import XCTest

@testable import TuistCoreTesting
@testable import TuistKit

final class ProjectFilesSortenerTests: XCTestCase {
    var fileHandler: MockFileHandler!
    var subject: ProjectFilesSortener!

    override func setUp() {
        super.setUp()
        fileHandler = try! MockFileHandler()
        subject = ProjectFilesSortener(fileHandler: fileHandler)
    }

    func test_sort() throws {
        // Given
        let basePath = fileHandler.currentPath
        let file1 = basePath.appending(RelativePath("path/to/sources/file.swift"))
        let file2 = basePath.appending(RelativePath("path/to/tests/test.swift"))
        let file3 = basePath.appending(RelativePath("path/to/tuist.swift"))
        let file4 = basePath.appending(RelativePath("path/to/waka.swift"))
        let files = [file1, file2, file3, file4]
        try files.forEach { try fileHandler.touch($0) }

        // When
        let got = files.sorted(by: subject.sort)

        // Then
        XCTAssertEqual(got[0], file3)
        XCTAssertEqual(got[1], file4)
        XCTAssertEqual(got[2], file1)
        XCTAssertEqual(got[3], file2)
    }
}
