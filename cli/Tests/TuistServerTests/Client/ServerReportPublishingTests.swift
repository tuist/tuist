import Foundation
import HTTPTypes
import Mockable
import OpenAPIRuntime
import Testing
import TuistEnvironment
import TuistHTTP

@testable import TuistServer

struct ServerReportPublishingTests {
    @Test(arguments: ["createBuild", "createBuild (2)", "createTest"])
    func only_reports_allow_a_genuinely_missing_token(operation: String) async throws {
        let url = try #require(URL(string: "https://tuist.example"))
        let authentication = MockServerAuthenticationControlling()
        given(authentication).authenticationToken(serverURL: .any, refreshIfNeeded: .value(true)).willReturn(nil)
        let middleware = ServerClientAuthenticationMiddleware(
            serverAuthenticationController: authentication,
            networkTrustedReports: true
        )
        let environment = Environment(variables: ["TUIST_NETWORK_TRUSTED_PUBLISHING": "true"], arguments: [])
        try await Environment.$current.withValue(environment) {
            try await confirmation("Report forwarded without credentials") { forwarded in
                _ = try await middleware.intercept(
                    HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/"),
                    body: nil,
                    baseURL: url,
                    operationID: operation
                ) { request, _, _ in
                    forwarded()
                    #expect(request.headerFields[.authorization] == nil)
                    return (HTTPResponse(status: .ok), nil)
                }
            }
            await #expect(throws: ClientAuthenticationError.notAuthenticated) {
                try await middleware.intercept(
                    HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/"),
                    body: nil,
                    baseURL: url,
                    operationID: "getCacheEndpoints"
                ) { _, _, _ in
                    Issue.record("Cache discovery must not be anonymous")
                    return (HTTPResponse(status: .ok), nil)
                }
            }
        }
    }

    @Test(arguments: ["https://tuist.dev", "https://CLOUD.TUIST.IO.", "https://canary.tuist.dev", "https://tuist.io"])
    func hosted_destinations_are_blocked(url: String) async throws {
        let authentication = MockServerAuthenticationControlling()
        given(authentication).authenticationToken(serverURL: .any, refreshIfNeeded: .value(true)).willReturn(nil)
        let middleware = ServerClientAuthenticationMiddleware(
            serverAuthenticationController: authentication,
            networkTrustedReports: true
        )
        let environment = Environment(variables: ["TUIST_NETWORK_TRUSTED_PUBLISHING": "true"], arguments: [])
        try await Environment.$current.withValue(environment) {
            await #expect(throws: ServerReportPublishingError.selfHostedDestinationRequired) {
                try await middleware.intercept(
                    HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/"),
                    body: nil,
                    baseURL: try #require(URL(string: url)),
                    operationID: "createBuild"
                ) { _, _, _ in
                    Issue.record("A report must not leave for a hosted destination")
                    return (HTTPResponse(status: .ok), nil)
                }
            }
        }
    }

    @Test func errors_and_blank_credentials_never_downgrade() async throws {
        let url = try #require(URL(string: "https://tuist.example"))
        let authentication = MockServerAuthenticationControlling()
        given(authentication).authenticationToken(serverURL: .any, refreshIfNeeded: .value(true))
            .willThrow(ServerReportPublishingError.invalidCredentials)
        let middleware = ServerClientAuthenticationMiddleware(
            serverAuthenticationController: authentication,
            networkTrustedReports: true
        )
        let environment = Environment(variables: ["TUIST_NETWORK_TRUSTED_PUBLISHING": "true"], arguments: [])
        try await Environment.$current.withValue(environment) {
            for _ in 0 ..< 2 {
                await #expect(throws: ServerReportPublishingError.invalidCredentials) {
                    try await middleware.intercept(
                        HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/"),
                        body: nil,
                        baseURL: url,
                        operationID: "createTest"
                    ) { _, _, _ in
                        Issue.record("Invalid credentials must not become anonymous")
                        return (HTTPResponse(status: .ok), nil)
                    }
                }
            }
            given(authentication).authenticationToken(serverURL: .any, refreshIfNeeded: .value(true)).willReturn(.project(" "))
            await #expect(throws: ServerReportPublishingError.invalidCredentials) {
                try await middleware.intercept(
                    HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/"),
                    body: nil,
                    baseURL: url,
                    operationID: "createTest"
                ) { _, _, _ in
                    Issue.record("Blank credentials must not become anonymous")
                    return (HTTPResponse(status: .ok), nil)
                }
            }
        }
    }

    @Test func supplied_credentials_are_kept() async throws {
        let url = try #require(URL(string: "https://tuist.example"))
        let authentication = MockServerAuthenticationControlling()
        given(authentication).authenticationToken(serverURL: .any, refreshIfNeeded: .value(true))
            .willReturn(.project("supplied-token"))
        let middleware = ServerClientAuthenticationMiddleware(
            serverAuthenticationController: authentication,
            networkTrustedReports: true
        )
        let environment = Environment(variables: ["TUIST_NETWORK_TRUSTED_PUBLISHING": "true"], arguments: [])
        try await Environment.$current.withValue(environment) {
            try await confirmation("Authenticated report forwarded") { forwarded in
                _ = try await middleware.intercept(
                    HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/"),
                    body: nil,
                    baseURL: url,
                    operationID: "createTest"
                ) { request, _, _ in
                    forwarded()
                    #expect(request.headerFields[.authorization] == "Bearer supplied-token")
                    return (HTTPResponse(status: .ok), nil)
                }
            }
        }
    }
}
