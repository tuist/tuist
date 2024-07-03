import Foundation
import MockableTest
import TuistLoader
import TuistServer
import TuistSupport
import TuistSupportTesting
import XcodeGraph
import XCTest
@testable import TuistKit

final class OrganizationInviteServiceTests: TuistUnitTestCase {
    private var createOrganizationInviteService: MockCreateOrganizationInviteServicing!
    private var subject: OrganizationInviteService!
    private var configLoader: MockConfigLoading!
    private var serverURL: URL!

    override func setUp() {
        super.setUp()

        createOrganizationInviteService = .init()
        configLoader = MockConfigLoading()
        serverURL = URL(string: "https://test.cloud.tuist.io")!
        given(configLoader).loadConfig(path: .any).willReturn(.test(url: serverURL))
        subject = OrganizationInviteService(
            createOrganizationInviteService: createOrganizationInviteService,
            configLoader: configLoader
        )
    }

    override func tearDown() {
        createOrganizationInviteService = nil
        configLoader = nil
        serverURL = nil
        subject = nil
        super.tearDown()
    }

    func test_invite() async throws {
        // Given
        given(createOrganizationInviteService)
            .createOrganizationInvite(
                organizationName: .value("tuist"),
                email: .value("tuist@test.io"),
                serverURL: .value(serverURL)
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

        You can also share with them the invite link directly: \(serverURL.absoluteString)/auth/invitations/invitation-token
        """)
    }
}
