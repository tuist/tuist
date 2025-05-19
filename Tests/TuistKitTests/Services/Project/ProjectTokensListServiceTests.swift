import Foundation
import Mockable
import ServiceContextModule
import TuistLoader
import TuistServer
import TuistSupportTesting
import XCTest

@testable import TuistKit

final class ProjectTokensListServiceTests: TuistUnitTestCase {
    private var listProjectTokensService: MockListProjectTokensServicing!
    private var serverURLService: MockServerURLServicing!
    private var configLoader: MockConfigLoading!
    private var serverURL: URL!
    private var subject: ProjectTokensListService!

    override func setUp() {
        super.setUp()

        listProjectTokensService = .init()
        serverURLService = .init()
        configLoader = .init()
        serverURL = URL(string: "https://test.tuist.dev")!
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(url: serverURL))
        given(serverURLService)
            .url(configServerURL: .value(serverURL))
            .willReturn(serverURL)
        subject = ProjectTokensListService(
            listProjectTokensService: listProjectTokensService,
            serverURLService: serverURLService,
            configLoader: configLoader
        )
    }

    override func tearDown() {
        listProjectTokensService = nil
        serverURLService = nil
        configLoader = nil
        serverURL = nil
        subject = nil

        super.tearDown()
    }

    func test_list_project_tokens() async throws {
        try await ServiceContext.withTestingDependencies {
            // Given
            let projectTokenOneInsertedAt = Date(timeIntervalSince1970: 0)
            let projectTokenTwoInsertedAt = Date(timeIntervalSince1970: 10)

            given(listProjectTokensService)
                .listProjectTokens(
                    fullHandle: .value("tuist-org/tuist"),
                    serverURL: .any
                )
                .willReturn(
                    [
                        .test(
                            id: "project-token-one",
                            insertedAt: projectTokenOneInsertedAt
                        ),
                        .test(
                            id: "project-token-two",
                            insertedAt: projectTokenTwoInsertedAt
                        ),
                    ]
                )

            // When
            try await subject.run(fullHandle: "tuist-org/tuist", directory: nil)

            // Then
            let formatter = DateFormatter()
            formatter.timeZone = TimeZone.gmt
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
            let formattedDateForProjectTokenOne = formatter.string(from: projectTokenOneInsertedAt)
            let formattedDateForProjectTokenTwo = formatter.string(from: projectTokenTwoInsertedAt)
            let divider = String(repeating: "─", count: formattedDateForProjectTokenOne.count)
            let createdAtHeading = "Created at"
            let trailingSpace = String(repeating: " ", count: formattedDateForProjectTokenOne.count - createdAtHeading.count)

            XCTAssertStandardOutput(
                pattern: """
                ID                 \(createdAtHeading)\(trailingSpace)
                ─────────────────  \(divider)
                project-token-one  \(formattedDateForProjectTokenOne)
                project-token-two  \(formattedDateForProjectTokenTwo)
                """
            )
        }
    }

    func test_list_project_tokens_when_none_present() async throws {
        try await ServiceContext.withTestingDependencies {
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
                pattern: "No project tokens found. Create one by running `tuist project tokens create tuist-org/tuist."
            )
        }
    }
}
