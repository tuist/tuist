import TSCBasic
import XCTest
@testable import TuistSigning
@testable import TuistSigningTesting
@testable import TuistSupportTesting

final class ProvisioningProfileParserTests: TuistTestCase {
    var provisioningProfileParser: ProvisioningProfileParser!

    override func setUp() {
        super.setUp()

        provisioningProfileParser = ProvisioningProfileParser()
    }

    override func tearDown() {
        super.tearDown()

        provisioningProfileParser = nil
    }

    func test_parse_provisioningProfile() throws {
        // Given
        let currentDirectory = AbsolutePath(#file.replacingOccurrences(of: "file://", with: "")).removingLastComponent()
        let provisioningProfileFile = currentDirectory.appending(component: "SignApp.debug.mobileprovision")
        let expectedProvisioningProfile = ProvisioningProfile(
            path: provisioningProfileFile,
            name: "SignApp.Debug",
            targetName: "SignApp",
            configurationName: "debug",
            uuid: "d34fb066-f494-4d85-a556-d469c2196f46",
            teamId: "QH95ER52SG",
            appId: "QH95ER52SG.io.tuist.SignApp",
            appIdName: "SignApp",
            applicationIdPrefix: ["QH95ER52SG"],
            platforms: ["iOS"],
            expirationDate: Date(timeIntervalSince1970: 1_619_208_757.0),
            developerCertificateFingerprints: ["SHA1 Fingerprint=80:B8:6E:55:1D:8E:F2:38:CD:95:3C:7E:72:3B:DB:B1:A5:B0:5D:60"]
        )

        // When
        let provisioningProfile = try provisioningProfileParser.parse(at: provisioningProfileFile)

        // Then
        XCTAssertEqual(provisioningProfile, expectedProvisioningProfile)
    }
}
