import Basic
import Foundation
import XCTest
@testable import TuistCore

final class FileHandlerErrorTests: XCTestCase {
    func test_description() {
        XCTAssertEqual(FileHandlerError.invalidTextEncoding(AbsolutePath("/path")).description, "The file at /path is not a utf8 text file")
        XCTAssertEqual(FileHandlerError.writingError(AbsolutePath("/path")).description, "Couldn't write to the file /path")
    }
}

final class FileHandlerTests: XCTestCase {
    private var subject: FileHandler!
    private let fileManager = FileManager.default

    // MARK: - Setup

    override func setUp() {
        super.setUp()

        subject = FileHandler()
    }

    // MARK: - Tests

    func test_replace() throws {
        // Given
        let tempFile = try TemporaryFile()
        let destFile = try TemporaryFile()
        try "content".write(to: tempFile.path.asURL, atomically: true, encoding: .utf8)

        // When
        try subject.replace(destFile.path, with: tempFile.path)

        // Then
        let content = try String(contentsOf: destFile.path.asURL)
        XCTAssertEqual(content, "content")
    }

    func test_replace_cleans_up_temp() throws {
        // Given
        let tempFile = try TemporaryFile()
        let destFile = try TemporaryFile()
        let count = try countItemsInRootTempDirectory(appropriateFor: destFile.path.asURL)

        // When
        try subject.replace(destFile.path, with: tempFile.path)

        // Then
        XCTAssertEqual(count, try countItemsInRootTempDirectory(appropriateFor: destFile.path.asURL))
    }
    
    func test_create_symlink() throws {
        // Given
        let destFile = try TemporaryFile()
        try "content".write(to: destFile.path.asURL, atomically: true, encoding: .utf8)
        let symlinkPath = destFile.path.removingLastComponent().appending(component: "create-symlink")
        
        // When
        try subject.createSymbolicLink(symlinkPath, destination: destFile.path)
        
        // Then
        XCTAssertEqual(try subject.readTextFile(destFile.path), try subject.readTextFile(symlinkPath))
        
        // Cleanup
        try subject.delete(symlinkPath)
    }
    
    func test_exists_does_not_follow_symlink() throws {
        // Given
        let destFile = try TemporaryFile()
        let symlinkPath = destFile.path.removingLastComponent().appending(component: "follow-symlink")
        try subject.createSymbolicLink(symlinkPath, destination: destFile.path)
        
        // When
        try subject.delete(destFile.path)
        
        // Then
        XCTAssertTrue(subject.exists(symlinkPath, followSymlink: false))
        XCTAssertFalse(subject.exists(symlinkPath, followSymlink: true))
        
        // Cleanup
        try subject.delete(symlinkPath)
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
