import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest
@testable import TuistCoreTesting
@testable import TuistSigning
@testable import TuistSigningTesting
@testable import TuistSupportTesting

final class SigningMapperTests: TuistUnitTestCase {
    var subject: SigningMapper!
    var signingFilesLocator: MockSigningFilesLocator!
    var signingMatcher: MockSigningMatcher!
    var signingCipher: MockSigningCipher!

    override func setUp() {
        super.setUp()
        signingFilesLocator = MockSigningFilesLocator()
        signingMatcher = MockSigningMatcher()
        signingCipher = MockSigningCipher()

        subject = SigningMapper(
            signingFilesLocator: signingFilesLocator,
            signingMatcher: signingMatcher,
            signingCipher: signingCipher
        )
    }

    override func tearDown() {
        signingFilesLocator = nil
        signingMatcher = nil
        signingCipher = nil
        subject = nil
        super.tearDown()
    }

    func test_signing_mapping() throws {
        // Given
        let signingDirectory = try temporaryPath()
        signingFilesLocator.locateSigningDirectoryStub = { _ in
            signingDirectory
        }

        let targetName = "target"
        let configuration = "configuration"
        let certificate = Certificate.test(name: "certA")
        let fingerprint = "fingerprint"
        let provisioningProfile = ProvisioningProfile.test(
            name: "profileA",
            teamId: "TeamID",
            appId: "TeamID.BundleID",
            developerCertificateFingerprints: ["otherFingerPrint", fingerprint]
        )
        signingMatcher.matchStub = { _ in
            (
                certificates: [
                    fingerprint: certificate,
                ],
                provisioningProfiles: [
                    targetName: [
                        configuration: provisioningProfile,
                    ],
                ]
            )
        }

        let target = Target.test(
            name: targetName,
            bundleId: "BundleID",
            settings: Settings(
                configurations: [
                    BuildConfiguration(
                        name: configuration,
                        variant: .debug
                    ): Configuration.test(settings: [
                        "SOME_SETTING": "Value",
                    ]),
                ]
            )
        )

        let project = Project.test(
            path: try temporaryPath(),
            targets: [target]
        )
        let derivedDirectory = project.path.appending(component: Constants.DerivedDirectory.name)
        let keychainPath = derivedDirectory.appending(component: Constants.DerivedDirectory.signingKeychain)

        let expectedConfigurations: [BuildConfiguration: Configuration] = [
            BuildConfiguration(
                name: configuration,
                variant: .debug
            ): Configuration.test(settings: [
                "SOME_SETTING": "Value",
                "CODE_SIGN_STYLE": "Manual",
                "CODE_SIGN_IDENTITY": SettingValue(stringLiteral: certificate.name),
                "OTHER_CODE_SIGN_FLAGS": SettingValue(stringLiteral: "--keychain \(keychainPath.pathString)"),
                "DEVELOPMENT_TEAM": SettingValue(stringLiteral: provisioningProfile.teamId),
                "PROVISIONING_PROFILE_SPECIFIER": SettingValue(stringLiteral: provisioningProfile.uuid),
            ]),
        ]

        // When
        let (mappedProject, sideEffects) = try subject.map(project: project)

        // Then
        XCTAssertEmpty(sideEffects)
        let configurations = mappedProject.targets
            .map(\.settings)
            .map { $0?.configurations }

        XCTAssertEqual(configurations.first, expectedConfigurations)
    }
}
