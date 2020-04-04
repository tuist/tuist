import Basic
import Foundation
import TuistSupport
import XCTest
@testable import TuistCoreTesting
@testable import TuistSigning
@testable import TuistSupportTesting

final class SigningInstallerTests: TuistUnitTestCase {
    var subject: SigningInstalling!
    var signingFilesLocator: MockSigningFilesLocator!
    var securityController: MockSecurityController!

    override func setUp() {
        super.setUp()
        try? ProcessEnv.setVar("TUIST_VERBOSE", value: "true")
        signingFilesLocator = MockSigningFilesLocator()
        securityController = MockSecurityController()
        subject = SigningInstaller(signingFilesLocator: signingFilesLocator,
                                   securityController: securityController)
    }

    override func tearDown() {
        signingFilesLocator = nil
        securityController = nil
        super.tearDown()
    }

    func test_provisioning_profile_is_installed() throws {
        // Given
        let uuidString = "c17e88b5-23bf-4427-8dca-e98bb7e7be4f"
        let xml = self.xml("""
        <key>AppIDName</key>
        <string>SignApp</string>
        <key>UUID</key>
        <string>\(uuidString)</string>
        """)
        let temporaryPath = try self.temporaryPath()
        let provisioningProfilePath = temporaryPath.appending(component: "profile.mobileProvision")
        try fileHandler.write(xml, path: provisioningProfilePath, atomically: true)

        let homeDirectory = try self.temporaryPath()
        fileHandler.homeDirectoryStub = homeDirectory

        signingFilesLocator.locateUnencryptedSigningFilesStub = {
            [$0.appending(component: "profile.mobileprovision")]
        }

        securityController.decodeFileStub = { _ in
            xml
        }

        // When
        try subject.installSigning(at: temporaryPath)

        // Then
        XCTAssertEqual(try fileHandler.readTextFile(homeDirectory
                           .appending(RelativePath("Library/MobileDevice/Provisioning Profiles/\(uuidString).mobileprovision"))),
                       xml)
    }

    func test_throws_when_uuid_not_found() throws {
        let xml = self.xml("""
        <key>AppIDName</key>
        <string>SignApp</string>
        """)
        let temporaryPath = try self.temporaryPath()
        let provisioningProfilePath = temporaryPath.appending(component: "profile.mobileprovision")
        try fileHandler.write(xml, path: provisioningProfilePath, atomically: true)

        let homeDirectory = try self.temporaryPath()
        fileHandler.homeDirectoryStub = homeDirectory

        signingFilesLocator.locateUnencryptedSigningFilesStub = {
            [$0.appending(component: "profile.mobileprovision")]
        }

        securityController.decodeFileStub = { _ in
            xml
        }

        // Then
        XCTAssertThrowsSpecific(try subject.installSigning(at: temporaryPath),
                                SigningInstallerError.invalidProvisioningProfile(provisioningProfilePath))
    }

    func test_certificate_is_imported() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let certificatePath = temporaryPath.appending(component: "development.cer")
        try fileHandler.write("CERT", path: certificatePath, atomically: true)

        signingFilesLocator.locateUnencryptedSigningFilesStub = {
            [$0.appending(component: "development.cer")]
        }

        var importedCertificatePath: AbsolutePath?
        securityController.importCertificateStub = {
            importedCertificatePath = $0
        }

        // When
        try subject.installSigning(at: temporaryPath)

        // Then
        XCTAssertEqual(importedCertificatePath, certificatePath)
    }

    private func xml(_ string: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            \(string)
        </dict>
        </plist>
        """
    }
}
