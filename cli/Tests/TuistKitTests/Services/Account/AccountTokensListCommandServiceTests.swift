import Foundation
import Mockable
import OpenAPIRuntime
import Testing
import TuistLoader
import TuistServer
import TuistSupport
import TuistTesting

@testable import TuistKit

struct AccountTokensListCommandServiceTests {
    private let subject: AccountTokensListCommandService
    private let listAccountTokensService = MockListAccountTokensServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let configLoader = MockConfigLoading()
    private let serverURL: URL

    init() {
        serverURL = URL(string: "https://test.tuist.dev")!
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(url: serverURL))
        given(serverEnvironmentService)
            .url(configServerURL: .value(serverURL))
            .willReturn(serverURL)
        subject = AccountTokensListCommandService(
            listAccountTokensService: listAccountTokensService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader
        )
    }

    @Test(.withMockedEnvironment(), .withMockedNoora) func list_account_tokens() async throws {
        // Given
        given(listAccountTokensService)
            .listAccountTokens(
                accountHandle: .value("tuist-org"),
                serverURL: .any
            )
            .willReturn(
                [
                    .init(
                        all_projects: true,
                        expires_at: nil,
                        id: "token-one",
                        inserted_at: Date(timeIntervalSince1970: 0),
                        name: "ci-token",
                        project_handles: nil,
                        scopes: [.project_colon_cache_colon_read, .project_colon_cache_colon_write]
                    ),
                    .init(
                        all_projects: false,
                        expires_at: Date(timeIntervalSince1970: 86400),
                        id: "token-two",
                        inserted_at: Date(timeIntervalSince1970: 10),
                        name: "deploy-token",
                        project_handles: ["project-a", "project-b"],
                        scopes: [.project_colon_previews_colon_write]
                    ),
                ]
            )

        // When
        try await subject.run(accountHandle: "tuist-org", path: nil, json: false)

        // Then
        #expect(ui().contains("project:cache") == true)
    }

    @Test(.withMockedEnvironment(), .withMockedNoora) func list_account_tokens_when_none_present() async throws {
        // Given
        given(listAccountTokensService)
            .listAccountTokens(
                accountHandle: .value("tuist-org"),
                serverURL: .any
            )
            .willReturn([])

        // When
        try await subject.run(accountHandle: "tuist-org", path: nil, json: false)

        // Then
        #expect(
            ui().contains(
                "No account tokens found. Create one by running `tuist account tokens create tuist-org --scopes <scopes> --name <name>`."
            ) == true
        )
    }

    @Test(.withMockedEnvironment(), .withMockedNoora) func list_account_tokens_json() async throws {
        // Given
        let token: Operations.listAccountTokens.Output.Ok.Body.jsonPayload.tokensPayloadPayload = .init(
            all_projects: true,
            expires_at: nil,
            id: "token-one",
            inserted_at: Date(timeIntervalSince1970: 0),
            name: "ci-token",
            project_handles: nil,
            scopes: [.project_colon_cache_colon_read, .project_colon_cache_colon_write]
        )
        given(listAccountTokensService)
            .listAccountTokens(
                accountHandle: .value("tuist-org"),
                serverURL: .any
            )
            .willReturn([token])

        // When
        try await subject.run(accountHandle: "tuist-org", path: nil, json: true)

        // Then
        let jsonEncoder = JSONEncoder()
        jsonEncoder.dateEncodingStrategy = .iso8601
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let tokensJSON = String(data: try jsonEncoder.encode([token]), encoding: .utf8)!
        #expect(ui().contains(tokensJSON))
    }
}
