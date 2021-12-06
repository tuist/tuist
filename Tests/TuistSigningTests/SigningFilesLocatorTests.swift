import Foundation
import TSCBasic
import TuistSupport
import XCTest
@testable import TuistCoreTesting
@testable import TuistSigning
@testable import TuistSupportTesting

final class SigningFilesLocatorTests: TuistUnitTestCase {
    var subject: SigningFilesLocator!
    var rootDirectoryLocator: MockRootDirectoryLocator!

    override func setUp() {
        super.setUp()
        rootDirectoryLocator = MockRootDirectoryLocator()
        subject = SigningFilesLocator(rootDirectoryLocator: rootDirectoryLocator)
    }

    override func tearDown() {
        subject = nil
        rootDirectoryLocator = nil
        super.tearDown()
    }

    func test_locate_encrypted_certificates() throws {
        // Given
        let rootDirectory = try temporaryPath()
        rootDirectoryLocator.locateStub = rootDirectory
        let signingDirectory = rootDirectory.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
        try fileHandler.createFolder(signingDirectory)
        let expectedFileNames = ["file.cer.encrypted", "file2.cer.encrypted"]
        try (["file", "file.txt", "file.encrypted"] + expectedFileNames)
            .map(signingDirectory.appending)
            .forEach(fileHandler.touch)
        let expectedFiles = expectedFileNames.map(signingDirectory.appending)

        // When
        let files = try subject.locateEncryptedCertificates(from: signingDirectory)

        // Then
        XCTAssertEqual(files, expectedFiles)
    }

    func test_locate_encrypted_private_keys() throws {
        // Given
        let rootDirectory = try temporaryPath()
        rootDirectoryLocator.locateStub = rootDirectory
        let signingDirectory = rootDirectory.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
        try fileHandler.createFolder(signingDirectory)
        let expectedFileNames = ["file.p12.encrypted", "file2.p12.encrypted"]
        try (["file", "file.txt", "file.encrypted"] + expectedFileNames)
            .map(signingDirectory.appending)
            .forEach(fileHandler.touch)
        let expectedFiles = expectedFileNames.map(signingDirectory.appending)

        // When
        let files = try subject.locateEncryptedPrivateKeys(from: signingDirectory)

        // Then
        XCTAssertEqual(files, expectedFiles)
    }

    func test_locate_signing_directory_when_exists() throws {
        // Given
        let rootDirectory = try temporaryPath()
        rootDirectoryLocator.locateStub = rootDirectory
        let expectedSigningDirectory = rootDirectory.appending(
            components: Constants.tuistDirectoryName,
            Constants.signingDirectoryName
        )
        try fileHandler.createFolder(expectedSigningDirectory)

        // When
        let signingDirectory = try subject.locateSigningDirectory(from: rootDirectory)

        // Then
        XCTAssertEqual(signingDirectory, expectedSigningDirectory)
    }

    func test_locate_provisioning_profiles() throws {
        // Given
        let rootDirectory = try temporaryPath()
        rootDirectoryLocator.locateStub = rootDirectory
        let signingDirectory = rootDirectory.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
        try fileHandler.createFolder(signingDirectory)
        let expectedFileNames = ["file.mobileprovision"]
        try (["file.cer", "file.cer.encrypted"] + expectedFileNames)
            .map(signingDirectory.appending)
            .forEach(fileHandler.touch)
        let expectedFiles = expectedFileNames.map(signingDirectory.appending)

        // When
        let files = try subject.locateProvisioningProfiles(from: signingDirectory)

        // Then
        XCTAssertEqual(files, expectedFiles)
    }

    func test_locate_unencrypted_certificates() throws {
        // Given
        let rootDirectory = try temporaryPath()
        rootDirectoryLocator.locateStub = rootDirectory
        let signingDirectory = rootDirectory.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
        try fileHandler.createFolder(signingDirectory)
        let expectedFileNames = ["file.cer"]
        try (["file.mobileprovision", "file.cer.encrypted"] + expectedFileNames)
            .map(signingDirectory.appending)
            .forEach(fileHandler.touch)
        let expectedFiles = expectedFileNames.map(signingDirectory.appending)

        // When
        let files = try subject.locateUnencryptedCertificates(from: signingDirectory)

        // Then
        XCTAssertEqual(files, expectedFiles)
    }

    func test_locate_unencrypted_private_keys() throws {
        // Given
        let rootDirectory = try temporaryPath()
        rootDirectoryLocator.locateStub = rootDirectory
        let signingDirectory = rootDirectory.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
        try fileHandler.createFolder(signingDirectory)
        let expectedFileNames = ["file.p12"]
        try (["file.mobileprovision", "file.p12.encrypted"] + expectedFileNames)
            .map(signingDirectory.appending)
            .forEach(fileHandler.touch)
        let expectedFiles = expectedFileNames.map(signingDirectory.appending)

        // When
        let files = try subject.locateUnencryptedPrivateKeys(from: signingDirectory)

        // Then
        XCTAssertEqual(files, expectedFiles)
    }
}
