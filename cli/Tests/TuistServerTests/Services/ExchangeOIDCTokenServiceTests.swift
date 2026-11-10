import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
import TuistEnvironment
import TuistEnvironmentTesting

@testable import TuistServer

struct ExchangeOIDCTokenServiceTests {
    @Test(.withMockedEnvironment(), arguments: [nil, "", " \n ", "my-tuist-account", " my-tuist-account \n"])
    func forwards_optional_account_without_changing_identity_token(accountHandle: String?) async throws {
        let environment = try #require(Environment.mocked)
        environment.variables = accountHandle.map { ["TUIST_OIDC_ACCOUNT": $0] } ?? [:]
        let expectedAccount = accountHandle?.contains("my-tuist-account") == true ? "my-tuist-account" : nil
        let subject = ExchangeOIDCTokenService(makeClient: { url in
            Client(serverURL: url, transport: OIDCExchangeTransport(accountHandle: expectedAccount))
        })

        let token = try await subject.exchangeOIDCToken(
            oidcToken: "fly-identity-token",
            serverURL: URL(string: "https://tuist.example")!
        )

        #expect(token == "tuist-access-token")
    }
}

private struct OIDCExchangeTransport: ClientTransport {
    let accountHandle: String?

    func send(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        #expect(baseURL.absoluteString == "https://tuist.example")
        #expect(request.method == .post)
        #expect(request.path == "/api/auth/oidc/token")
        #expect(operationID == "exchangeOIDCToken")
        let body = try #require(body)
        let data = try await Data(collecting: body, upTo: 4096)
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(payload["token"] == "fly-identity-token")
        #expect(payload["account_handle"] == accountHandle)
        #expect(payload.count == (accountHandle == nil ? 1 : 2))

        var response = HTTPResponse(status: .ok)
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(#"{"access_token":"tuist-access-token","expires_in":3600}"#))
    }
}
