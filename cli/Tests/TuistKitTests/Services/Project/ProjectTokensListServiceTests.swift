import Foundation
import Mockable
import TuistLoader
import TuistServer
import TuistTesting
import XCTest

@testable import TuistKit

final class ProjectTokensListServiceTests: TuistUnitTestCase {
    private var listProjectTokensService: MockListProjectTokensServicing!
    private var serverEnvironmentService: MockServerEnvironmentServicing!
    private var configLoader: MockConfigLoading!
    private var serverURL: URL!
    private var subject: ProjectTokensListService!

    override func setUp() {
        super.setUp()

        listProjectTokensService = .init()
        serverEnvironmentService = .init()
        configLoader = .init()
        serverURL = URL(string: "https://test.tuist.dev")!
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(url: serverURL))
        given(serverEnvironmentService)
            .url(configServerURL: .value(serverURL))
            .willReturn(serverURL)
        subject = ProjectTokensListService(
            listProjectTokensService: listProjectTokensService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader
        )
    }

    override func tearDown() {
        listProjectTokensService = nil
        serverEnvironmentService = nil
        configLoader = nil
        serverURL = nil
        subject = nil

        super.tearDown()
    }

    func test_list_project_tokens() async throws {
        try await withMockedDependencies {
            // Given
            given(listProjectTokensService)
                .listProjectTokens(
                    fullHandle: .value("tuist-org/tuist"),
                    serverURL: .any
                )
                .willReturn(
                    [
                        .test(
                            id: "project-token-one",
                            insertedAt: Date(timeIntervalSince1970: 0)
                        ),
                        .test(
                            id: "project-token-two",
                            insertedAt: Date(timeIntervalSince1970: 10)
                        ),
                    ]
                )

            // When
            try await subject.run(fullHandle: "tuist-org/tuist", directory: nil)

            // Then
            XCTAssertStandardOutput(
                pattern: """
                ID                 Created at               
                ─────────────────  ─────────────────────────
                project-token-one  1970-01-01 00:00:00 +0000
                project-token-two  1970-01-01 00:00:10 +0000
                """
            )
        }
    }

    func test_list_project_tokens_when_none_present() async throws {
        try await withMockedDependencies {
            // Given
            given(listProjectTokensService)
                .listProjectTokens(
                    fullHandle: .value("tuist-org/tuist"),
                    serverURL: .any
                )
                .willReturn([])

            // When
            try await subject.run(fullHandle: "tuist-org/tuist", directory: nil)

            // Then
            XCTAssertStandardOutput(
                pattern:
                "No project tokens found. Create one by running `tuist project tokens create tuist-org/tuist."
            )
        }
    }
}
