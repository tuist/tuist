import Foundation
import MockableTest
import TuistLoader
import TuistServer
import TuistSupport
import TuistSupportTesting
import XcodeGraph
import XCTest
@testable import TuistKit

final class CloudOrganizationInviteServiceTests: TuistUnitTestCase {
    private var createOrganizationInviteService: MockCreateOrganizationInviteServicing!
    private var subject: CloudOrganizationInviteService!
    private var configLoader: MockConfigLoading!
    private var cloudURL: URL!

    override func setUp() {
        super.setUp()

        createOrganizationInviteService = .init()
        configLoader = MockConfigLoading()
        cloudURL = URL(string: "https://test.cloud.tuist.io")!
        given(configLoader).loadConfig(path: .any).willReturn(.test(cloud: .test(url: cloudURL)))
        subject = CloudOrganizationInviteService(
            createOrganizationInviteService: createOrganizationInviteService,
            configLoader: configLoader
        )
    }

    override func tearDown() {
        createOrganizationInviteService = nil
        configLoader = nil
        cloudURL = nil
        subject = nil
        super.tearDown()
    }

    func test_invite() async throws {
        // Given
        given(createOrganizationInviteService)
            .createOrganizationInvite(
                organizationName: .value("tuist"),
                email: .value("tuist@test.io"),
                serverURL: .value(cloudURL)
            )
            .willReturn(
                .test(
                    inviteeEmail: "tuist@test.io",
                    token: "invitation-token"
                )
            )

        // When
        try await subject.run(
            organizationName: "tuist",
            email: "tuist@test.io",
            directory: nil
        )

        // Then
        XCTAssertPrinterOutputContains("""
        tuist@test.io was successfully invited to the tuist organization 🎉

        You can also share with them the invite link directly: \(cloudURL.absoluteString)/auth/invitations/invitation-token
        """)
    }
}
