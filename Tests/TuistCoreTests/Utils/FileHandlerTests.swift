import XCTest
import Foundation
import Basic
@testable import TuistCore

final class FileHandlerTests: XCTestCase {

    private let fileManager = FileManager.default


    func test_replace_cleans_up_temp() throws {
        // Given
        let subject = FileHandler()
        let tempFile = try TemporaryFile()
        let destFile = try TemporaryFile()
        let count = try countItemsInRootTempDirectory(appropriateFor: destFile.path.asURL)

        // When
        try subject.replace(destFile.path, with: tempFile.path)

        // Then
        XCTAssertEqual(count, try countItemsInRootTempDirectory(appropriateFor: destFile.path.asURL))
    }

    // MARK: - Private

    private func countItemsInRootTempDirectory(appropriateFor url: URL) throws -> Int {
        let tempPath = AbsolutePath(try fileManager.url(for: .itemReplacementDirectory,
                                                        in: .userDomainMask,
                                                        appropriateFor: url,
                                                        create: false).path)
        let rootTempPath = tempPath.parentDirectory
        try fileManager.removeItem(at: tempPath.asURL)
        let content = try fileManager.contentsOfDirectory(atPath: rootTempPath.pathString)
        return content.count
    }
}
