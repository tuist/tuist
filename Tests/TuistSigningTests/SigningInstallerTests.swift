import Foundation
import TSCBasic
import TuistSupport
import XCTest
@testable import TuistCoreTesting
@testable import TuistSigning
@testable import TuistSigningTesting
@testable import TuistSupportTesting

final class SigningInstallerTests: TuistUnitTestCase {
    var subject: SigningInstalling!
    var securityController: MockSecurityController!

    override func setUp() {
        super.setUp()
        securityController = MockSecurityController()
        subject = SigningInstaller(securityController: securityController)
    }

    override func tearDown() {
        securityController = nil
        subject = nil
        super.tearDown()
    }

    func test_installing_provisioning_profile_fails_when_expired() throws {
        // Given
        let provisioningProfile = ProvisioningProfile.test(expirationDate: Date().addingTimeInterval(-1))

        // When
        XCTAssertThrowsSpecific(
            try subject.installProvisioningProfile(provisioningProfile),
            SigningInstallerError.expiredProvisioningProfile(provisioningProfile)
        )
    }

    func test_installling_provisioning_profile_fails_when_no_path() throws {
        // Given
        let provisioningProfile = ProvisioningProfile.test(path: nil)

        // When
        XCTAssertThrowsSpecific(
            try subject.installProvisioningProfile(provisioningProfile),
            SigningInstallerError.provisioningProfilePathNotFound(provisioningProfile)
        )
    }

    func test_installing_provisioning_profile_fails_when_no_extension() throws {
        // Given
        let provisioningProfilePath = try temporaryPath().appending(component: "file")
        let provisioningProfile = ProvisioningProfile.test(path: provisioningProfilePath)

        // When
        XCTAssertThrowsSpecific(
            try subject.installProvisioningProfile(provisioningProfile),
            SigningInstallerError.noFileExtension(provisioningProfilePath)
        )
    }

    func test_provisioning_profile_is_installed() throws {
        // Given
        let homeDirectoryPath = try temporaryPath()
        fileHandler.homeDirectoryStub = homeDirectoryPath
        let provisioningProfilesDirectoryPath = homeDirectoryPath.appending(RelativePath("Library/MobileDevice/Provisioning Profiles"))
        let sourceProvisioningProfilePath = try temporaryPath().appending(component: "file.mobileprovision")
        try "my provisioning".write(to: sourceProvisioningProfilePath.url, atomically: true, encoding: .utf8)
        let provisioningProfile = ProvisioningProfile.test(
            path: sourceProvisioningProfilePath,
            uuid: UUID().uuidString
        )
        let destinationProvisioningProfilePath = provisioningProfilesDirectoryPath.appending(component: "\(provisioningProfile.uuid).mobileprovision")

        // When
        try subject.installProvisioningProfile(provisioningProfile)

        // Then
        XCTAssertEqual(
            try fileHandler.readFile(sourceProvisioningProfilePath),
            try fileHandler.readFile(destinationProvisioningProfilePath)
        )
    }

    func test_certificate_is_imported() throws {
        // Given
        let expectedCertificate = Certificate.test()
        let expectedPath = try temporaryPath()
        var certificate: Certificate?
        var path: AbsolutePath?
        securityController.importCertificateStub = {
            certificate = $0
            path = $1
        }

        // When
        try subject.installCertificate(expectedCertificate, keychainPath: expectedPath)

        // Then
        XCTAssertEqual(expectedCertificate, certificate)
        XCTAssertEqual(expectedPath, path)
    }
}
