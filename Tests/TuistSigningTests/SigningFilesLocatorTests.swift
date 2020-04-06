import Basic
import Foundation
import TuistSupport
import XCTest
@testable import TuistCoreTesting
@testable import TuistSigning
@testable import TuistSupportTesting

final class SigningFilesLocatorTests: TuistUnitTestCase {
    var subject: SigningFilesLocator!

    override func setUp() {
        super.setUp()
        subject = SigningFilesLocator()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_locate_encrypted_signing_files() throws {
        // Given
        let signingDirectory = try temporaryPath().appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
        try fileHandler.createFolder(signingDirectory)
        let expectedFileNames = ["file.encrypted", "file2.encrypted"]
        try (["file", "file.txt", "file.not_encrypted"] + expectedFileNames)
            .map(signingDirectory.appending)
            .forEach(fileHandler.touch)
        let expectedFiles = expectedFileNames.map(signingDirectory.appending)

        // When
        let files = try subject.locateEncryptedSigningFiles(at: signingDirectory)

        // Then
        XCTAssertEqual(files, expectedFiles)
    }

    func test_locate_unencrypted_signing_files() throws {
        // Given
        let signingDirectory = try temporaryPath().appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
        try fileHandler.createFolder(signingDirectory)
        let expectedFileNames = ["file", "file.txt"]
        try (["file.encrypted"] + expectedFileNames)
            .map(signingDirectory.appending)
            .forEach(fileHandler.touch)
        let expectedFiles = expectedFileNames.map(signingDirectory.appending)

        // When
        let files = try subject.locateUnencryptedSigningFiles(at: signingDirectory)

        // Then
        XCTAssertEqual(files, expectedFiles)
    }
    
    func test_has_signing_directory_when_none_exists() throws {
        // Given
        let tuistDirectory = try temporaryPath().appending(components: Constants.tuistDirectoryName)
        try fileHandler.createFolder(tuistDirectory)
        
        // When
        let exists = try subject.hasSigningDirectory(at: tuistDirectory)
        
        // Then
        XCTAssertFalse(exists)
    }
    
    func test_has_signing_directory_when_exists() throws {
        // Given
        let tuistDirectory = try temporaryPath().appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
        try fileHandler.createFolder(tuistDirectory)
        
        // When
        let exists = try subject.hasSigningDirectory(at: tuistDirectory)
        
        // Then
        XCTAssertTrue(exists)
    }
}
