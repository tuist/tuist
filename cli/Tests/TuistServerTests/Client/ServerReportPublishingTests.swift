import Foundation
import HTTPTypes
import Mockable
import OpenAPIRuntime
import Testing
import TuistEnvironment
import TuistHTTP

@testable import TuistServer

struct ServerReportPublishingTests {
    @Test(arguments: [
        (200, #"{"network_trusted_report_publishing":true,"future":{"version":2,"capabilities":["unknown"]}}"#, true),
        (200, #"{"network_trusted_report_publishing":false}"#, false),
        (200, #"{"network_trusted_report_publishing":"true"}"#, false),
        (200, #"{"network_trusted_report_publishing":null}"#, false),
        (200, #"{"network_trusted_report_publishing":{"enabled":true}}"#, false),
        (200, "[]", false),
        (200, "{}", false),
        (200, "not json", false),
        (302, #"{"network_trusted_report_publishing":true}"#, false),
        (404, "{}", false),
        (503, "{}", false),
    ])
    func discovery_requires_an_explicit_boolean(status: Int, body: String, allowed: Bool) async throws {
        let url = try #require(URL(string: "https://tuist.example"))
        let result = try await ServerReportPublishingMode.discover(url) { request in
            #expect(request.url?.absoluteString == "https://tuist.example/.well-known/tuist.json")
            #expect(request.httpMethod == "GET")
            #expect(request.httpBody == nil)
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "x-tuist-actor-id") == nil)
            return (
                Data(body.utf8),
                try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
            )
        }
        #expect(result == allowed)
    }

    @Test func discovery_transport_errors_are_not_permission_to_publish() async throws {
        let url = try #require(URL(string: "https://tuist.example"))
        await #expect(throws: URLError.self) {
            try await ServerReportPublishingMode.discover(url) { _ in throw URLError(.timedOut) }
        }
    }

    @Test(arguments: ["createBuild", "createBuild (2)", "createTest"])
    func only_reports_allow_a_genuinely_missing_token(operation: String) async throws {
        let url = try #require(URL(string: "https://tuist.example"))
        let authentication = MockServerAuthenticationControlling()
        given(authentication).authenticationToken(serverURL: .any, refreshIfNeeded: .value(true)).willReturn(nil)
        let middleware = ServerClientAuthenticationMiddleware(
            serverAuthenticationController: authentication,
            networkTrustedReports: true,
            networkTrustedPublishing: true
        )
        try await ServerReportPublishingMode.$serverAllowsNetworkPublishing.withValue({ _ in
            Issue.record("Transport must use the payload's pinned mode without rediscovering it")
            return false
        }) {
            try await confirmation("Report forwarded without credentials") { forwarded in
                _ = try await middleware.intercept(
                    HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/"),
                    body: nil, baseURL: url, operationID: operation
                ) { request, _, _ in
                    forwarded()
                    #expect(request.headerFields[.authorization] == nil)
                    return (HTTPResponse(status: .ok), nil)
                }
            }
            await #expect(throws: ClientAuthenticationError.notAuthenticated) {
                try await middleware.intercept(
                    HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/"),
                    body: nil, baseURL: url, operationID: "getCacheEndpoints"
                ) { _, _, _ in
                    Issue.record("Cache discovery must not be anonymous")
                    return (HTTPResponse(status: .ok), nil)
                }
            }
        }
    }

    @Test func disabled_or_older_servers_require_authentication() async throws {
        let url = try #require(URL(string: "https://tuist.example"))
        let authentication = MockServerAuthenticationControlling()
        given(authentication).authenticationToken(serverURL: .any, refreshIfNeeded: .value(true)).willReturn(nil)
        given(authentication).authenticationToken(serverURL: .any).willReturn(nil)
        let middleware = ServerClientAuthenticationMiddleware(
            serverAuthenticationController: authentication, networkTrustedReports: true
        )
        try await ServerReportPublishingMode.$serverAllowsNetworkPublishing.withValue({ _ in false }) {
            let networkPublishing = try await ServerReportPublishingMode.usesNetworkTrust(
                serverURL: url, authenticationController: authentication
            )
            #expect(!networkPublishing)
            await #expect(throws: ClientAuthenticationError.notAuthenticated) {
                try await middleware.intercept(
                    HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/"),
                    body: nil, baseURL: url, operationID: "createTest"
                ) { _, _, _ in
                    Issue.record("The server must advertise credential-free publishing")
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
            serverAuthenticationController: authentication, networkTrustedReports: true
        )
        try await ServerReportPublishingMode.$serverAllowsNetworkPublishing.withValue({ _ in
            Issue.record("Hosted destinations must not be probed")
            return true
        }) {
            await #expect(throws: ClientAuthenticationError.notAuthenticated) {
                try await middleware.intercept(
                    HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/"),
                    body: nil, baseURL: try #require(URL(string: url)), operationID: "createBuild"
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
            serverAuthenticationController: authentication, networkTrustedReports: true
        )
        try await ServerReportPublishingMode.$serverAllowsNetworkPublishing.withValue({ _ in
            Issue.record("Invalid credentials must fail before discovery")
            return true
        }) {
            for _ in 0 ..< 2 {
                let thrown = await #expect(throws: CredentialAcquisitionError.self) {
                    try await middleware.intercept(
                        HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/"),
                        body: nil, baseURL: url, operationID: "createTest"
                    ) { _, _, _ in
                        Issue.record("Invalid credentials must not become anonymous")
                        return (HTTPResponse(status: .ok), nil)
                    }
                }
                #expect(thrown?.underlyingError as? ServerReportPublishingError == .invalidCredentials)
            }
            authentication.reset()
            given(authentication).authenticationToken(serverURL: .any, refreshIfNeeded: .value(true)).willReturn(.project(" "))
            await #expect(throws: ServerReportPublishingError.invalidCredentials) {
                try await middleware.intercept(
                    HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/"),
                    body: nil, baseURL: url, operationID: "createTest"
                ) { _, _, _ in
                    Issue.record("Blank credentials must not become anonymous")
                    return (HTTPResponse(status: .ok), nil)
                }
            }
        }
    }

    @Test func blank_environment_tokens_are_rejected_without_client_opt_in() async throws {
        let url = try #require(URL(string: "https://tuist.example"))
        let environment = Environment(variables: ["TUIST_TOKEN": ""], arguments: [])
        try await Environment.$current.withValue(environment) {
            let authentication = ServerAuthenticationController()
            let token = try await authentication.authenticationToken(serverURL: url)
            #expect(token == .project(""))
            await #expect(throws: ServerReportPublishingError.invalidCredentials) {
                try await ServerReportPublishingMode.usesNetworkTrust(
                    serverURL: url, authenticationController: authentication
                )
            }
        }
    }

    @Test func disabled_discovery_cannot_be_replaced_by_a_later_positive_response() async throws {
        let url = try #require(URL(string: "https://tuist.example"))
        let authentication = MockServerAuthenticationControlling()
        given(authentication).authenticationToken(serverURL: .any).willReturn(nil)
        given(authentication).authenticationToken(serverURL: .any, refreshIfNeeded: .value(true)).willReturn(nil)
        let networkTrusted = try await ServerReportPublishingMode.$serverAllowsNetworkPublishing.withValue({ _ in false }) {
            try await ServerReportPublishingMode.usesNetworkTrust(serverURL: url, authenticationController: authentication)
        }
        #expect(!networkTrusted)
        let middleware = ServerClientAuthenticationMiddleware(
            serverAuthenticationController: authentication, networkTrustedReports: true,
            networkTrustedPublishing: networkTrusted
        )
        try await ServerReportPublishingMode.$serverAllowsNetworkPublishing.withValue({ _ in
            Issue.record("An authenticated payload must not be downgraded by a second discovery")
            return true
        }) {
            await #expect(throws: ClientAuthenticationError.notAuthenticated) {
                try await middleware.intercept(
                    HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/"),
                    body: HTTPBody("privileged payload"), baseURL: url, operationID: "createTest"
                ) { _, _, _ in
                    Issue.record("An authenticated payload must never be sent unsigned")
                    return (HTTPResponse(status: .ok), nil)
                }
            }
        }
    }

    @Test func disappearing_credentials_cannot_downgrade_an_authenticated_payload() async throws {
        let url = try #require(URL(string: "https://tuist.example"))
        let authentication = MockServerAuthenticationControlling()
        given(authentication).authenticationToken(serverURL: .any).willReturn(.project("present-during-construction"))
        given(authentication).authenticationToken(serverURL: .any, refreshIfNeeded: .value(true)).willReturn(nil)
        let networkTrusted = try await ServerReportPublishingMode.$serverAllowsNetworkPublishing.withValue({ _ in
            Issue.record("Existing credentials must prevent discovery")
            return true
        }) {
            try await ServerReportPublishingMode.usesNetworkTrust(serverURL: url, authenticationController: authentication)
        }
        let middleware = ServerClientAuthenticationMiddleware(
            serverAuthenticationController: authentication, networkTrustedReports: true,
            networkTrustedPublishing: networkTrusted
        )
        await #expect(throws: ClientAuthenticationError.notAuthenticated) {
            try await middleware.intercept(
                HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/"),
                body: nil, baseURL: url, operationID: "createTest"
            ) { _, _, _ in
                Issue.record("Credentials disappearing must not cause an unsigned publication")
                return (HTTPResponse(status: .ok), nil)
            }
        }
    }

    @Test func supplied_credentials_are_kept_without_discovery() async throws {
        let url = try #require(URL(string: "https://tuist.example"))
        let authentication = MockServerAuthenticationControlling()
        given(authentication).authenticationToken(serverURL: .any, refreshIfNeeded: .value(true))
            .willReturn(.project("supplied-token"))
        let middleware = ServerClientAuthenticationMiddleware(
            serverAuthenticationController: authentication, networkTrustedReports: true
        )
        try await ServerReportPublishingMode.$serverAllowsNetworkPublishing.withValue({ _ in
            Issue.record("Authenticated reporting must not need discovery")
            return false
        }) {
            try await confirmation("Authenticated report forwarded") { forwarded in
                _ = try await middleware.intercept(
                    HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/"),
                    body: nil, baseURL: url, operationID: "createTest"
                ) { request, _, _ in
                    forwarded()
                    #expect(request.headerFields[.authorization] == "Bearer supplied-token")
                    return (HTTPResponse(status: .ok), nil)
                }
            }
        }
    }
}
