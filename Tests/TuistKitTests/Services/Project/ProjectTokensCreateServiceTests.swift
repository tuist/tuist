import Foundation
import MockableTest
import TuistLoader
import TuistServer
import TuistSupportTesting
import XCTest

@testable import TuistKit

final class ProjectTokensCreateServiceTests: TuistUnitTestCase {
    private var createProjectTokenService: MockCreateProjectTokenServicing!
    private var serverURLService: MockServerURLServicing!
    private var configLoader: MockConfigLoading!
    private var serverURL: URL!
    private var subject: ProjectTokensCreateService!

    override func setUp() {
        super.setUp()

        createProjectTokenService = .init()
        serverURLService = .init()
        configLoader = .init()
        serverURL = URL(string: "https://test.cloud.tuist.io")!
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(url: serverURL))
        given(serverURLService)
            .url(configServerURL: .value(serverURL))
            .willReturn(serverURL)
        subject = ProjectTokensCreateService(
            createProjectTokenService: createProjectTokenService,
            serverURLService: serverURLService,
            configLoader: configLoader
        )
    }

    override func tearDown() {
        createProjectTokenService = nil
        serverURLService = nil
        configLoader = nil
        serverURL = nil
        subject = nil

        super.tearDown()
    }

    func test_create_project_token() async throws {
        // Given
        given(createProjectTokenService)
            .createProjectToken(
                fullHandle: .value("tuist-org/tuist"),
                serverURL: .any
            )
            .willReturn("new-token")

        // When
        try await subject.run(fullHandle: "tuist-org/tuist", directory: nil)

        // Then
        XCTAssertStandardOutput(pattern: "new-token")
    }
}
