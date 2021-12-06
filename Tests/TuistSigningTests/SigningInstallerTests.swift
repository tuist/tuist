import Foundation
import TSCBasic
import TuistCore
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

    func test_installing_provisioning_profile_is_installed_warns_when_expired() throws {
        // Given
        let sourceProvisioningProfilePath = try generateTestProfileFile()
        let provisioningProfile = ProvisioningProfile.test(
            path: sourceProvisioningProfilePath,
            expirationDate: Date().addingTimeInterval(-1)
        )

        // When
        let issues = try subject.installProvisioningProfile(provisioningProfile)
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(
            issues.first,
            LintingIssue.expiredProvisioningProfile(provisioningProfile)
        )
        XCTAssertTrue(try isProfileInstalled(provisioningProfile))
    }

    func test_installing_provisioning_profile_fails_when_no_extension() throws {
        // Given
        let provisioningProfilePath = try temporaryPath().appending(component: "file")
        let provisioningProfile = ProvisioningProfile.test(path: provisioningProfilePath)

        // When
        let issues = try subject.installProvisioningProfile(provisioningProfile)
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(
            issues.first,
            LintingIssue.noFileExtension(provisioningProfilePath)
        )
    }

    func test_provisioning_profile_is_installed() throws {
        // Given
        let sourceProvisioningProfilePath = try generateTestProfileFile()
        let provisioningProfile = ProvisioningProfile.test(
            path: sourceProvisioningProfilePath,
            uuid: UUID().uuidString
        )

        // When
        let issues = try subject.installProvisioningProfile(provisioningProfile)

        // Then
        XCTAssertEmpty(issues)
        XCTAssertTrue(try isProfileInstalled(provisioningProfile))
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

    private func generateTestProfileFile() throws -> AbsolutePath {
        let sourceProvisioningProfilePath = try temporaryPath().appending(component: "file.mobileprovision")
        try "my provisioning".write(to: sourceProvisioningProfilePath.url, atomically: true, encoding: .utf8)

        return sourceProvisioningProfilePath
    }

    private func isProfileInstalled(_ profile: ProvisioningProfile) throws -> Bool {
        let homeDirectoryPath = try temporaryPath()
        fileHandler.homeDirectoryStub = homeDirectoryPath
        let provisioningProfilesDirectoryPath = homeDirectoryPath
            .appending(RelativePath("Library/MobileDevice/Provisioning Profiles"))
        let destinationProvisioningProfilePath = provisioningProfilesDirectoryPath
            .appending(component: "\(profile.uuid).mobileprovision")

        return fileHandler.exists(destinationProvisioningProfilePath)
    }
}
