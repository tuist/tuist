import TSCBasic
import Foundation
import TuistSupport
import XCTest
@testable import TuistCoreTesting
@testable import TuistSigning
@testable import TuistSupportTesting

final class SecurityControllerTests: TuistUnitTestCase {
    var subject: SecurityController!

    override func setUp() {
        super.setUp()
        subject = SecurityController()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_decode_file() throws {
        // Given
        let decodeFilePath = try temporaryPath()

        let expectedOutput = "output"
        system.succeedCommand("/usr/bin/security", "cms", "-D", "-i", decodeFilePath.pathString, output: expectedOutput)

        // When
        let output = try subject.decodeFile(at: decodeFilePath)

        // Then
        XCTAssertEqual(expectedOutput, output)
    }

    func test_import_certificate_succeeds() throws {
        // Given
        let certificatePath = try temporaryPath()
        let homeDirectoryPath = try temporaryPath()
        fileHandler.homeDirectoryStub = homeDirectoryPath
        let keychainPath = homeDirectoryPath.appending(RelativePath("Library/Keychains/login.keychain"))

        system.succeedCommand("/usr/bin/security", "-p", keychainPath.pathString, "import", certificatePath.pathString)

        // Then
        XCTAssertNoThrow(try subject.importCertificate(at: certificatePath))
    }

    func test_skips_certificate_when_already_imported() throws {
        // Given
        let certificatePath = try temporaryPath()
        let homeDirectoryPath = try temporaryPath()
        fileHandler.homeDirectoryStub = homeDirectoryPath
        let keychainPath = homeDirectoryPath.appending(RelativePath("Library/Keychains/login.keychain"))
        system.errorCommand("/usr/bin/security", "-p", keychainPath.pathString, "import", certificatePath.pathString,
                            error: "security: SecKeychainItemImport: The specified item already exists in the keychain.")

        // When
        try subject.importCertificate(at: certificatePath)

        // Then
        XCTAssertPrinterContains("Certificate at \(certificatePath) is already present in keychain", at: .debug, ==)
    }
}
