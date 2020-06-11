import TSCBasic
import TuistSupport
import XCTest
@testable import TuistSigning
@testable import TuistSigningTesting
@testable import TuistSupportTesting

final class SecurityControllerIntegrationTests: TuistTestCase {
    var subject: SecurityController!

    override func setUp() {
        super.setUp()

        subject = SecurityController()
    }

    override func tearDown() {
        super.tearDown()

        subject = nil
    }

    func test_import_certificate() throws {
        // Given
        let keychainPath = try temporaryPath().appending(component: Constants.signingKeychain)

        let currentDirectory = AbsolutePath(#file.replacingOccurrences(of: "file://", with: "")).removingLastComponent()
        let publicKey = currentDirectory.appending(component: "Target.Debug.cer")
        let privateKey = currentDirectory.appending(component: "Target.Debug.p12")

        try subject.createKeychain(at: keychainPath, password: "")
        try subject.unlockKeychain(at: keychainPath, password: "")

        let certificate = Certificate.test(
            publicKey: publicKey,
            privateKey: privateKey
        )

        // When
        try subject.importCertificate(certificate, keychainPath: keychainPath)

        // Then
        XCTAssertPrinterContains(
            "Imported certificate at \(certificate.publicKey.pathString)",
            at: .debug,
            ==
        )
        XCTAssertPrinterContains(
            "Imported certificate private key at \(certificate.privateKey.pathString)",
            at: .debug,
            ==
        )
    }

    func test_import_certificate_when_exists() throws {
        // Given
        let keychainPath = try temporaryPath().appending(component: Constants.signingKeychain)

        let currentDirectory = AbsolutePath(#file.replacingOccurrences(of: "file://", with: "")).removingLastComponent()
        let publicKey = currentDirectory.appending(component: "Target.Debug.cer")
        let privateKey = currentDirectory.appending(component: "Target.Debug.p12")

        try subject.createKeychain(at: keychainPath, password: "")
        try subject.unlockKeychain(at: keychainPath, password: "")

        let certificate = Certificate.test(
            publicKey: publicKey,
            privateKey: privateKey
        )

        // When
        try subject.importCertificate(certificate, keychainPath: keychainPath)
        try subject.importCertificate(certificate, keychainPath: keychainPath)

        // Then
        XCTAssertPrinterContains(
            "Skipping importing certificate at \(certificate.publicKey.pathString) because it is already present",
            at: .debug,
            ==
        )
        XCTAssertPrinterContains(
            "Skipping importing private key at \(certificate.privateKey.pathString) because it is already present",
            at: .debug,
            ==
        )
    }

    func test_decode_file() throws {
        // Given
        let currentDirectory = AbsolutePath(#file.replacingOccurrences(of: "file://", with: "")).removingLastComponent()
        let provisioningProfile = currentDirectory.appending(component: "SignApp.debug.mobileprovision")

        // When
        let output = try subject.decodeFile(at: provisioningProfile)

        // Then
        XCTAssertFalse(output.isEmpty)
    }
}
