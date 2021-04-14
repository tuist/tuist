import TSCBasic
import XCTest
@testable import TuistSigning
@testable import TuistSupportTesting

final class ProvisioningProfileParserTests: TuistUnitTestCase {
    var subject: ProvisioningProfileParser!
    var securityController: MockSecurityController!

    override func setUp() {
        super.setUp()
        securityController = MockSecurityController()

        subject = ProvisioningProfileParser(
            securityController: securityController
        )
    }

    override func tearDown() {
        super.tearDown()

        securityController = nil
        subject = nil
    }

    func test_parse_provisioning_profile() throws {
        // Given
        let path = try temporaryPath().appending(component: "Target.Configuration.mobileprovision")
        let expectedProvisioningProfile = ProvisioningProfile(
            path: path,
            name: "SomeRandomName",
            targetName: "Target",
            configurationName: "Configuration",
            uuid: "UUID",
            teamId: "TeamID",
            appId: "AppID",
            appIdName: "AppIDName",
            applicationIdPrefix: ["Prefix"],
            platforms: ["iOS"],
            expirationDate: Date(timeIntervalSinceReferenceDate: 640_729_461),
            developerCertificateFingerprints: []
        )
        securityController.decodeFileStub = { _ in
            .testProvisioningProfile(
                name: "SomeRandomName",
                uuid: "UUID",
                teamId: "TeamID",
                appId: "AppID",
                appIdName: "AppIDName",
                applicationIdPrefix: "Prefix",
                platform: "iOS",
                expirationDate: "2021-04-21T20:24:21Z"
            )
        }

        // When
        let provisioningProfile = try subject.parse(at: path)

        // Then
        XCTAssertEqual(provisioningProfile, expectedProvisioningProfile)
    }
}

private extension String {
    static func testProvisioningProfile(
        name: String,
        uuid: String,
        teamId: String,
        appId: String,
        appIdName: String,
        applicationIdPrefix: String,
        platform: String,
        expirationDate: String
    ) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>AppIDName</key>
            <string>\(appIdName)</string>
            <key>ApplicationIdentifierPrefix</key>
            <array>
            <string>\(applicationIdPrefix)</string>
            </array>
            <key>CreationDate</key>
            <date>2020-04-21T20:24:21Z</date>
            <key>Platform</key>
            <array>
                <string>\(platform)</string>
            </array>
            <key>Entitlements</key>
            <dict>

                        <key>application-identifier</key>
                <string>\(appId)</string>

                        <key>keychain-access-groups</key>
                <array>
                        <string>QH95ER52SG.*</string>
                </array>

                        <key>get-task-allow</key>
                <true/>

                        <key>com.apple.developer.team-identifier</key>
                <string>QH95ER52SG</string>

            </dict>
            <key>ExpirationDate</key>
            <date>\(expirationDate)</date>
            <key>Name</key>
            <string>\(name)</string>
            <key>DeveloperCertificates</key>
            <array>
            </array>
            <key>ProvisionedDevices</key>
            <array>
                <string>2b41533fd2df499800f493b261d060fe6d60838b</string>
                <string>c15c854d86cf93daaece5c4a0149c327158f39ac</string>
                <string>4eb7158af203c058bf499eb2a8b471efeaa5b409</string>
                <string>a34fa7dbe6a41e1a03f8490fed2471352c49f9b1</string>
                <string>5007d1d5a42448b7b1b00f7bb105692f926c9994</string>
                <string>85ae2ab5296d4e9c1144086930fd9ad123597727</string>
                <string>fb51810d1c13a3020571cda0067c7bddd6ddc11e</string>
                <string>026a773757d5cff1286982ea15ceaa75631cfce0</string>
                <string>ba9f742fbbbf5667d47622b50989f3f4b6ceeb94</string>
                <string>f3b9fec27b685fc2d252bf30f0afe4dc1df0793c</string>
                <string>a1986b2845626748803229585256bcbcfa169044</string>
                <string>6336361bc160e48f6b418ba6e5265d9b102cd059</string>
                <string>b577234f6eca19ef2cfa20e79ed51e27d5a740e5</string>
                <string>3bc0dcd2308e9008daf383c0f888592cece42758</string>
            </array>
            <key>TeamIdentifier</key>
            <array>
                <string>\(teamId)</string>
            </array>
            <key>TeamName</key>
            <string>Marek Fort</string>
            <key>TimeToLive</key>
            <integer>365</integer>
            <key>UUID</key>
            <string>\(uuid)</string>
            <key>Version</key>
            <integer>1</integer>
        </dict>
        </plist>
        """
    }
}
