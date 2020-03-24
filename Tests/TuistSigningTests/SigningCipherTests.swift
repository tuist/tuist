import Basic
import Foundation
import XCTest
import TuistSupport
@testable import TuistSigning
@testable import TuistSupportTesting
@testable import TuistCoreTesting

final class SigningCipherTests: TuistUnitTestCase {
    var subject: SigningCiphering!
    var rootDirectoryLocator: MockRootDirectoryLocator!
        
    override func setUp() {
        super.setUp()
        rootDirectoryLocator = MockRootDirectoryLocator()
        subject = SigningCipher(rootDirectoryLocator: rootDirectoryLocator)
    }
    
    override func tearDown() {
        rootDirectoryLocator = nil
        subject = nil
        super.tearDown()
    }

    func test_fails_when_no_master_key() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        try FileHandler.shared.createFolder(temporaryPath.appending(component: Constants.tuistDirectoryName))
        let masterKeyPath = temporaryPath.appending(component: Constants.masterKey)
        rootDirectoryLocator.locateStub = temporaryPath
        // Then
        XCTAssertThrowsSpecific(try subject.encryptSigning(at: temporaryPath),
                                SigningCipherError.masterKeyNotFound(masterKeyPath))
    }
    
    func test_encrypt_and_decrypt_signing() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        rootDirectoryLocator.locateStub = temporaryPath
        let signingDirectory = temporaryPath.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
        try FileHandler.shared.createFolder(signingDirectory)
        try FileHandler.shared.write("my-password", path: temporaryPath.appending(component: Constants.masterKey), atomically: true)
        let certContent = "my-certificate"
        let profileContent = "my-profile"
        let certFile = signingDirectory.appending(component: "CertFile.txt")
        let profileFile = signingDirectory.appending(component: "ProfileFile.txt")
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
        rootDirectoryLocator.locateStub = temporaryPath
        let signingDirectory = temporaryPath.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
        try FileHandler.shared.createFolder(signingDirectory)
        try FileHandler.shared.write("my-password",
                                     path: temporaryPath.appending(component: Constants.masterKey),
                                     atomically: true)
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
