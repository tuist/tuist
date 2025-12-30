import Foundation
import Mockable
import Testing
import TuistLoader
import TuistServer
import TuistSupport
import TuistTesting

@testable import TuistKit

struct AccountTokensCreateCommandServiceTests {
    private let subject: AccountTokensCreateCommandService
    private let createAccountTokenService = MockCreateAccountTokenServicing()
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
        subject = AccountTokensCreateCommandService(
            createAccountTokenService: createAccountTokenService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader
        )
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies(), .withMockedNoora) func create_account_token() async throws {
        // Given
        given(createAccountTokenService)
            .createAccountToken(
                accountHandle: .value("tuist-org"),
                scopes: .value([.project_colon_cache_colon_read, .project_colon_cache_colon_write]),
                name: .value("ci-token"),
                expiresAt: .any,
                projectHandles: .value(nil),
                serverURL: .any
            )
            .willReturn(.init(id: "token-id", token: "generated-token-value"))

        // When
        try await subject.run(
            accountHandle: "tuist-org",
            scopes: [.project_colon_cache_colon_read, .project_colon_cache_colon_write],
            name: "ci-token",
            expires: nil,
            projects: nil,
            path: nil
        )

        // Then
        #expect(ui().contains("generated-token-value") == true)
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedDependencies(),
        .withMockedNoora
    ) func create_account_token_with_expiration() async throws {
        // Given
        given(createAccountTokenService)
            .createAccountToken(
                accountHandle: .value("tuist-org"),
                scopes: .any,
                name: .value("temp-token"),
                expiresAt: .matching { $0 != nil },
                projectHandles: .value(nil),
                serverURL: .any
            )
            .willReturn(.init(id: "token-id", token: "expiring-token"))

        // When
        try await subject.run(
            accountHandle: "tuist-org",
            scopes: [.project_colon_cache_colon_read],
            name: "temp-token",
            expires: "30d",
            projects: nil,
            path: nil
        )

        // Then
        #expect(ui().contains("expiring-token") == true)
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedDependencies(),
        .withMockedNoora
    ) func create_account_token_with_specific_projects() async throws {
        // Given
        given(createAccountTokenService)
            .createAccountToken(
                accountHandle: .value("tuist-org"),
                scopes: .any,
                name: .value("project-token"),
                expiresAt: .any,
                projectHandles: .value(["project-a", "project-b"]),
                serverURL: .any
            )
            .willReturn(.init(id: "token-id", token: "project-specific-token"))

        // When
        try await subject.run(
            accountHandle: "tuist-org",
            scopes: [.project_colon_previews_colon_write],
            name: "project-token",
            expires: nil,
            projects: ["project-a", "project-b"],
            path: nil
        )

        // Then
        #expect(ui().contains("project-specific-token") == true)
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedDependencies()
    ) func create_account_token_with_invalid_expires_format() async throws {
        // When/Then
        await #expect(throws: AccountTokensCreateCommandServiceError.invalidExpiresDuration("invalid")) {
            try await subject.run(
                accountHandle: "tuist-org",
                scopes: [.project_colon_cache_colon_read],
                name: "test-token",
                expires: "invalid",
                projects: nil,
                path: nil
            )
        }
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedDependencies(),
        .withMockedLogger()
    ) func create_account_token_parses_days() async throws {
        // Given
        given(createAccountTokenService)
            .createAccountToken(
                accountHandle: .value("tuist-org"),
                scopes: .value([.project_colon_cache_colon_read]),
                name: .value("test-token"),
                expiresAt: .matching { $0 != nil },
                projectHandles: .value(nil),
                serverURL: .any
            )
            .willReturn(.init(id: "token-id", token: "token"))

        // When
        try await subject.run(
            accountHandle: "tuist-org",
            scopes: [.project_colon_cache_colon_read],
            name: "test-token",
            expires: "30d",
            projects: nil,
            path: nil
        )

        // Then
        verify(createAccountTokenService)
            .createAccountToken(
                accountHandle: .any,
                scopes: .any,
                name: .any,
                expiresAt: .matching { date in
                    guard let date else { return false }
                    let calendar = Calendar.current
                    let days = calendar.dateComponents([.day], from: Date(), to: date).day ?? 0
                    return days >= 29 && days <= 31
                },
                projectHandles: .any,
                serverURL: .any
            )
            .called(1)
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedDependencies(),
        .withMockedLogger()
    ) func create_account_token_parses_months() async throws {
        // Given
        given(createAccountTokenService)
            .createAccountToken(
                accountHandle: .value("tuist-org"),
                scopes: .value([.project_colon_cache_colon_read]),
                name: .value("test-token"),
                expiresAt: .matching { $0 != nil },
                projectHandles: .value(nil),
                serverURL: .any
            )
            .willReturn(.init(id: "token-id", token: "token"))

        // When
        try await subject.run(
            accountHandle: "tuist-org",
            scopes: [.project_colon_cache_colon_read],
            name: "test-token",
            expires: "6m",
            projects: nil,
            path: nil
        )

        // Then
        verify(createAccountTokenService)
            .createAccountToken(
                accountHandle: .any,
                scopes: .any,
                name: .any,
                expiresAt: .matching { date in
                    guard let date else { return false }
                    let calendar = Calendar.current
                    let months = calendar.dateComponents([.month], from: Date(), to: date).month ?? 0
                    return months >= 5 && months <= 7
                },
                projectHandles: .any,
                serverURL: .any
            )
            .called(1)
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedDependencies(),
        .withMockedLogger()
    ) func create_account_token_parses_years() async throws {
        // Given
        given(createAccountTokenService)
            .createAccountToken(
                accountHandle: .value("tuist-org"),
                scopes: .value([.project_colon_cache_colon_read]),
                name: .value("test-token"),
                expiresAt: .matching { $0 != nil },
                projectHandles: .value(nil),
                serverURL: .any
            )
            .willReturn(.init(id: "token-id", token: "token"))

        // When
        try await subject.run(
            accountHandle: "tuist-org",
            scopes: [.project_colon_cache_colon_read],
            name: "test-token",
            expires: "1y",
            projects: nil,
            path: nil
        )

        // Then
        verify(createAccountTokenService)
            .createAccountToken(
                accountHandle: .any,
                scopes: .any,
                name: .any,
                expiresAt: .matching { date in
                    guard let date else { return false }
                    let calendar = Calendar.current
                    let days = calendar.dateComponents([.day], from: Date(), to: date).day ?? 0
                    return days == 364
                },
                projectHandles: .any,
                serverURL: .any
            )
            .called(1)
    }
}
