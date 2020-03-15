import Basic
import Foundation
import XCTest
import TuistSupport
@testable import TuistSigning
@testable import TuistSupportTesting

final class SigningCipherTests: TuistUnitTestCase {
    var subject: SigningCiphering!
        
    override func setUp() {
        subject = SigningCipher()
    }

    func test_fails_when_no_master_key() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        try FileHandler.shared.createFolder(temporaryPath.appending(component: Constants.tuistDirectoryName))
        let masterKeyPath = temporaryPath.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName, "master.key")
        // Then
        XCTAssertThrowsSpecific(try subject.encryptSigning(at: temporaryPath), SigningCipherError.masterKeyNotFound(masterKeyPath))
    }
    
    func test_encrypt_and_decrypt_signing() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let signingDirectory = temporaryPath.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
        try FileHandler.shared.createFolder(signingDirectory)
        try FileHandler.shared.write("my-password", path: signingDirectory.appending(component: "master.key"), atomically: true)
        let certContent = "my-certificate"
        let profileContent = "my-profile"
        let certFile = signingDirectory.appending(component: "CertFile.txt")
        let profileFile = signingDirectory.appending(component: "ProfileFile.text")
        try FileHandler.shared.write(certContent, path: certFile, atomically: true)
        try FileHandler.shared.write(profileContent, path: profileFile, atomically: true)
        
        // When
        try subject.encryptSigning(at: temporaryPath)
        try subject.decryptSigning(at: temporaryPath)
        
        // Then
        XCTAssertEqual(try FileHandler.shared.readTextFile(certFile), certContent)
        XCTAssertEqual(try FileHandler.shared.readTextFile(profileFile), profileContent)
    }
    
    func test_encrypt_signing() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let signingDirectory = temporaryPath.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
        try FileHandler.shared.createFolder(signingDirectory)
        try FileHandler.shared.write("my-password", path: signingDirectory.appending(component: "master.key"), atomically: true)
        let certContent = "my-certificate"
        let profileContent = "my-profile"
        let certFile = signingDirectory.appending(component: "CertFile.txt")
        let profileFile = signingDirectory.appending(component: "ProfileFile.text")
        try FileHandler.shared.write(certContent, path: certFile, atomically: true)
        try FileHandler.shared.write(profileContent, path: profileFile, atomically: true)
        
        // When
        try subject.encryptSigning(at: temporaryPath)
        
        // Then
        XCTAssertNotEqual(try FileHandler.shared.readTextFile(certFile), certContent)
        XCTAssertNotEqual(try FileHandler.shared.readTextFile(profileFile), profileContent)
    }
}
