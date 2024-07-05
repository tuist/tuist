import Foundation
import MockableTest
import TuistLoader
import TuistServer
import TuistSupportTesting
import XCTest

@testable import TuistKit

final class ProjectTokensRevokeServiceTests: TuistUnitTestCase {
    private var revokeProjectTokenService: MockRevokeProjectTokenServicing!
    private var serverURLService: MockServerURLServicing!
    private var configLoader: MockConfigLoading!
    private var serverURL: URL!
    private var subject: ProjectTokensRevokeService!

    override func setUp() {
        super.setUp()

        revokeProjectTokenService = .init()
        serverURLService = .init()
        configLoader = .init()
        serverURL = URL(string: "https://test.cloud.tuist.io")!
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(url: serverURL))
        given(serverURLService)
            .url(configServerURL: .value(serverURL))
            .willReturn(serverURL)
        subject = ProjectTokensRevokeService(
            revokeProjectTokenService: revokeProjectTokenService,
            serverURLService: serverURLService,
            configLoader: configLoader
        )
    }

    override func tearDown() {
        revokeProjectTokenService = nil
        serverURLService = nil
        configLoader = nil
        serverURL = nil
        subject = nil

        super.tearDown()
    }

    func test_revoke_project_token() async throws {
        // Given
        given(revokeProjectTokenService)
            .revokeProjectToken(
                projectTokenId: .value("project-token-id"),
                fullHandle: .value("tuist-org/tuist"),
                serverURL: .any
            )
            .willReturn()

        // When
        try await subject.run(
            projectTokenId: "project-token-id",
            fullHandle: "tuist-org/tuist",
            directory: nil
        )

        // Then
        XCTAssertStandardOutput(pattern: "The project token project-token-id was successfully revoked.")
    }
}
