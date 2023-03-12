import Foundation
import TSCBasic
import TuistSupport
import XCTest
@testable import TuistCoreTesting
@testable import TuistSigning
@testable import TuistSupportTesting

final class SigningCipherTests: TuistUnitTestCase {
    var subject: SigningCiphering!
    var rootDirectoryLocator: MockRootDirectoryLocator!
    var signingFilesLocator: MockSigningFilesLocator!

    override func setUp() {
        super.setUp()
        rootDirectoryLocator = MockRootDirectoryLocator()
        signingFilesLocator = MockSigningFilesLocator()
        subject = SigningCipher(
            rootDirectoryLocator: rootDirectoryLocator,
            signingFilesLocator: signingFilesLocator
        )
    }

    override func tearDown() {
        rootDirectoryLocator = nil
        signingFilesLocator = nil
        subject = nil
        super.tearDown()
    }

    func test_fails_when_no_master_key() throws {
        // Given
        let temporaryPath = try temporaryPath()
        rootDirectoryLocator.locateStub = temporaryPath
        try FileHandler.shared.createFolder(temporaryPath.appending(component: Constants.tuistDirectoryName))
        let masterKeyPath = temporaryPath.appending(components: Constants.tuistDirectoryName, Constants.masterKey)
        rootDirectoryLocator.locateStub = temporaryPath
        // Then
        XCTAssertThrowsSpecific(
            try subject.encryptSigning(at: temporaryPath, keepFiles: false),
            SigningCipherError.masterKeyNotFound(masterKeyPath)
        )
    }

    func test_encrypt_and_decrypt_signing() throws {
        // Given
        let temporaryPath = try temporaryPath()
        rootDirectoryLocator.locateStub = temporaryPath
        let signingDirectory = temporaryPath.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
        try FileHandler.shared.createFolder(signingDirectory)
        try FileHandler.shared.write(
            "my-password",
            path: temporaryPath.appending(components: Constants.tuistDirectoryName, Constants.masterKey),
            atomically: true
        )
        let certContent = "my-certificate"
        let profileContent = "my-profile"
        signingFilesLocator.locateUnencryptedCertificatesStub = { path in
            let signingDirectory = path.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
            return [
                signingDirectory.appending(component: "CertFile.txt"),
            ]
        }
        signingFilesLocator.locateUnencryptedPrivateKeysStub = { path in
            let signingDirectory = path.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
            return [
                signingDirectory.appending(component: "ProfileFile.txt"),
            ]
        }
        signingFilesLocator.locateEncryptedCertificatesStub = { path in
            let signingDirectory = path.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
            return [
                try AbsolutePath(validating: signingDirectory.pathString + "/CertFile.txt" + "." + Constants.encryptedExtension),
            ]
        }
        signingFilesLocator.locateEncryptedPrivateKeysStub = { path in
            let signingDirectory = path.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
            return [
                try AbsolutePath(
                    validating: signingDirectory.pathString + "/ProfileFile.txt" + "." + Constants
                        .encryptedExtension
                ),
            ]
        }
        let certFile = signingDirectory.appending(component: "CertFile.txt")
        let profileFile = signingDirectory.appending(component: "ProfileFile.txt")
        try FileHandler.shared.write(certContent, path: certFile, atomically: true)
        try FileHandler.shared.write(profileContent, path: profileFile, atomically: true)

        // When
        try subject.encryptSigning(at: temporaryPath, keepFiles: false)
        try subject.decryptSigning(at: temporaryPath, keepFiles: false)

        // Then
        XCTAssertEqual(try fileHandler.readTextFile(certFile), certContent)
        XCTAssertEqual(try fileHandler.readTextFile(profileFile), profileContent)
        XCTAssertFalse(
            fileHandler
                .exists(try AbsolutePath(
                    validating: signingDirectory.pathString + "/ProfileFile.txt" + "." + Constants
                        .encryptedExtension
                ))
        )
        XCTAssertFalse(
            fileHandler
                .exists(try AbsolutePath(
                    validating: signingDirectory.pathString + "/CertFile.txt" + "." + Constants
                        .encryptedExtension
                ))
        )
    }

    func test_decrypt_signing_when_master_key_has_newline() throws {
        // Given
        let temporaryPath = try temporaryPath()
        rootDirectoryLocator.locateStub = temporaryPath
        let signingDirectory = temporaryPath.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
        try FileHandler.shared.createFolder(signingDirectory)
        try FileHandler.shared.write(
            "my-password",
            path: temporaryPath.appending(components: Constants.tuistDirectoryName, Constants.masterKey),
            atomically: true
        )
        let certContent = "my-certificate"
        let profileContent = "my-profile"
        signingFilesLocator.locateUnencryptedCertificatesStub = { path in
            let signingDirectory = path.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
            return [
                signingDirectory.appending(component: "CertFile.txt"),
            ]
        }
        signingFilesLocator.locateUnencryptedPrivateKeysStub = { path in
            let signingDirectory = path.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
            return [
                signingDirectory.appending(component: "ProfileFile.txt"),
            ]
        }
        signingFilesLocator.locateEncryptedCertificatesStub = { path in
            let signingDirectory = path.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
            return [
                try AbsolutePath(validating: signingDirectory.pathString + "/CertFile.txt" + "." + Constants.encryptedExtension),
            ]
        }
        signingFilesLocator.locateEncryptedPrivateKeysStub = { path in
            let signingDirectory = path.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
            return [
                try AbsolutePath(
                    validating: signingDirectory.pathString + "/ProfileFile.txt" + "." + Constants
                        .encryptedExtension
                ),
            ]
        }
        let certFile = signingDirectory.appending(component: "CertFile.txt")
        let profileFile = signingDirectory.appending(component: "ProfileFile.txt")
        try FileHandler.shared.write(certContent, path: certFile, atomically: true)
        try FileHandler.shared.write(profileContent, path: profileFile, atomically: true)

        // When
        try subject.encryptSigning(at: temporaryPath, keepFiles: false)
        try FileHandler.shared.write(
            "my-password\n",
            path: temporaryPath.appending(components: Constants.tuistDirectoryName, Constants.masterKey),
            atomically: true
        )
        try subject.decryptSigning(at: temporaryPath, keepFiles: false)

        // Then
        XCTAssertEqual(try fileHandler.readTextFile(certFile), certContent)
        XCTAssertEqual(try fileHandler.readTextFile(profileFile), profileContent)
        XCTAssertFalse(
            fileHandler
                .exists(try AbsolutePath(
                    validating: signingDirectory.pathString + "/ProfileFile.txt" + "." + Constants
                        .encryptedExtension
                ))
        )
        XCTAssertFalse(
            fileHandler
                .exists(try AbsolutePath(
                    validating: signingDirectory.pathString + "/CertFile.txt" + "." + Constants
                        .encryptedExtension
                ))
        )
    }

    func test_encrypt_signing() throws {
        // Given
        let temporaryPath = try temporaryPath()
        rootDirectoryLocator.locateStub = temporaryPath
        let signingDirectory = temporaryPath.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
        try FileHandler.shared.createFolder(signingDirectory)
        try FileHandler.shared.write(
            "my-password",
            path: temporaryPath.appending(components: Constants.tuistDirectoryName, Constants.masterKey),
            atomically: true
        )
        let certContent = "my-certificate"
        let profileContent = "my-profile"
        let certFile = signingDirectory.appending(component: "CertFile.txt")
        let profileFile = signingDirectory.appending(component: "ProfileFile.txt")
        try FileHandler.shared.write(certContent, path: certFile, atomically: true)
        try FileHandler.shared.write(profileContent, path: profileFile, atomically: true)
        signingFilesLocator.locateUnencryptedCertificatesStub = { path in
            let signingDirectory = path.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
            return [
                signingDirectory.appending(component: "CertFile.txt"),
            ]
        }
        signingFilesLocator.locateUnencryptedPrivateKeysStub = { path in
            let signingDirectory = path.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
            return [
                signingDirectory.appending(component: "ProfileFile.txt"),
            ]
        }

        let encryptedCertFile = try AbsolutePath(validating: certFile.pathString + "." + Constants.encryptedExtension)
        let encryptedProfileFile = try AbsolutePath(validating: profileFile.pathString + "." + Constants.encryptedExtension)

        // When
        try subject.encryptSigning(at: temporaryPath, keepFiles: false)

        // Then
        XCTAssertNotEqual(try FileHandler.shared.readTextFile(encryptedCertFile), certContent)
        XCTAssertNotEqual(try FileHandler.shared.readTextFile(encryptedProfileFile), profileContent)
    }

    func test_encrypt_deletes_unencrypted_files() throws {
        // Given
        let temporaryPath = try temporaryPath()
        rootDirectoryLocator.locateStub = temporaryPath
        let signingDirectory = temporaryPath.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
        try FileHandler.shared.createFolder(signingDirectory)
        try FileHandler.shared.write(
            "my-password",
            path: temporaryPath.appending(components: Constants.tuistDirectoryName, Constants.masterKey),
            atomically: true
        )
        let certContent = "my-certificate"
        let profileContent = "my-profile"
        let certFile = signingDirectory.appending(component: "CertFile.txt")
        let profileFile = signingDirectory.appending(component: "ProfileFile.txt")
        try FileHandler.shared.write(certContent, path: certFile, atomically: true)
        try FileHandler.shared.write(profileContent, path: profileFile, atomically: true)
        signingFilesLocator.locateUnencryptedCertificatesStub = { path in
            let signingDirectory = path.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
            return [
                signingDirectory.appending(component: "CertFile.txt"),
            ]
        }
        signingFilesLocator.locateUnencryptedPrivateKeysStub = { path in
            let signingDirectory = path.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
            return [
                signingDirectory.appending(component: "ProfileFile.txt"),
            ]
        }

        // When
        try subject.encryptSigning(at: temporaryPath, keepFiles: false)

        // Then
        XCTAssertFalse(fileHandler.exists(certFile))
        XCTAssertFalse(fileHandler.exists(profileFile))
    }

    func test_encrypt_does_not_delete_unencrypted_files_when_keep_files_true() throws {
        // Given
        let temporaryPath = try temporaryPath()
        rootDirectoryLocator.locateStub = temporaryPath
        let signingDirectory = temporaryPath.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
        try FileHandler.shared.createFolder(signingDirectory)
        try FileHandler.shared.write(
            "my-password",
            path: temporaryPath.appending(components: Constants.tuistDirectoryName, Constants.masterKey),
            atomically: true
        )
        let certContent = "my-certificate"
        let profileContent = "my-profile"
        let certFile = signingDirectory.appending(component: "CertFile.txt")
        let profileFile = signingDirectory.appending(component: "ProfileFile.txt")
        try FileHandler.shared.write(certContent, path: certFile, atomically: true)
        try FileHandler.shared.write(profileContent, path: profileFile, atomically: true)
        signingFilesLocator.locateUnencryptedCertificatesStub = { path in
            let signingDirectory = path.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
            return [
                signingDirectory.appending(component: "CertFile.txt"),
            ]
        }
        signingFilesLocator.locateUnencryptedPrivateKeysStub = { path in
            let signingDirectory = path.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
            return [
                signingDirectory.appending(component: "ProfileFile.txt"),
            ]
        }

        // When
        try subject.encryptSigning(at: temporaryPath, keepFiles: true)

        // Then
        XCTAssertTrue(fileHandler.exists(certFile))
        XCTAssertTrue(fileHandler.exists(profileFile))
    }

    func test_encrypted_file_stays_the_same_when_unecrypted_file_has_not_changed() throws {
        // Given
        let temporaryPath = try temporaryPath()
        rootDirectoryLocator.locateStub = temporaryPath
        let signingDirectory = temporaryPath.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
        try FileHandler.shared.createFolder(signingDirectory)
        try FileHandler.shared.write(
            "my-password",
            path: temporaryPath.appending(components: Constants.tuistDirectoryName, Constants.masterKey),
            atomically: true
        )
        let certContent = "my-certificate"
        let profileContent = "my-profile"
        let certFile = signingDirectory.appending(component: "CertFile.txt")
        let profileFile = signingDirectory.appending(component: "ProfileFile.txt")
        let encryptedCertFile = try AbsolutePath(validating: certFile.pathString + "." + Constants.encryptedExtension)
        let encryptedProfileFile = try AbsolutePath(validating: profileFile.pathString + "." + Constants.encryptedExtension)
        try FileHandler.shared.write(certContent, path: certFile, atomically: true)
        try FileHandler.shared.write(profileContent, path: profileFile, atomically: true)
        signingFilesLocator.locateUnencryptedCertificatesStub = { path in
            let signingDirectory = path.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
            return [
                signingDirectory.appending(component: "CertFile.txt"),
            ]
        }
        signingFilesLocator.locateUnencryptedPrivateKeysStub = { path in
            let signingDirectory = path.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
            return [
                signingDirectory.appending(component: "ProfileFile.txt"),
            ]
        }
        try subject.encryptSigning(at: temporaryPath, keepFiles: true)
        let expectedCertFile = try fileHandler.readTextFile(encryptedCertFile)
        let expectedProfileFile = try fileHandler.readTextFile(encryptedProfileFile)
        signingFilesLocator.locateUnencryptedCertificatesStub = { _ in
            [certFile]
        }
        signingFilesLocator.locateUnencryptedPrivateKeysStub = { _ in
            [profileFile]
        }

        // When
        try subject.encryptSigning(at: temporaryPath, keepFiles: true)

        // Then
        XCTAssertEqual(try fileHandler.readTextFile(encryptedCertFile), expectedCertFile)
        XCTAssertEqual(try fileHandler.readTextFile(encryptedProfileFile), expectedProfileFile)
    }
}
