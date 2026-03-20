import Foundation
import HTTPTypes
import Testing

@testable import TuistHTTP

struct VerboseLoggingMiddlewareTests {
    @Test func redacts_authorization_header() {
        let headers: HTTPFields = [
            .authorization: "Bearer secret-token-123",
            .contentType: "application/json",
        ]

        let result = VerboseLoggingMiddleware.redactSensitiveHeaders(headers)

        #expect(result.contains("Authorization: [REDACTED]"))
        #expect(!result.contains("secret-token-123"))
        #expect(result.contains("Content-Type: application/json"))
    }

    @Test func redacts_cookie_headers() {
        let headers: HTTPFields = [
            .cookie: "session=abc123",
            .setCookie: "session=xyz789",
        ]

        let result = VerboseLoggingMiddleware.redactSensitiveHeaders(headers)

        #expect(result.contains("Cookie: [REDACTED]"))
        #expect(result.contains("Set-Cookie: [REDACTED]"))
        #expect(!result.contains("abc123"))
        #expect(!result.contains("xyz789"))
    }

    @Test func redacts_custom_sensitive_headers() {
        var headers = HTTPFields()
        headers.append(HTTPField(name: HTTPField.Name("X-API-Key")!, value: "my-api-key"))
        headers.append(HTTPField(name: HTTPField.Name("X-Auth-Token")!, value: "my-auth-token"))
        headers.append(HTTPField(name: HTTPField.Name("X-Access-Token")!, value: "my-access-token"))

        let result = VerboseLoggingMiddleware.redactSensitiveHeaders(headers)

        #expect(result.contains("[REDACTED]"))
        #expect(!result.contains("my-api-key"))
        #expect(!result.contains("my-auth-token"))
        #expect(!result.contains("my-access-token"))
    }

    @Test func preserves_non_sensitive_headers() {
        let headers: HTTPFields = [
            .contentType: "application/json",
            .accept: "text/html",
        ]

        let result = VerboseLoggingMiddleware.redactSensitiveHeaders(headers)

        #expect(result.contains("Content-Type: application/json"))
        #expect(result.contains("Accept: text/html"))
        #expect(!result.contains("[REDACTED]"))
    }

    @Test func handles_empty_headers() {
        let headers = HTTPFields()

        let result = VerboseLoggingMiddleware.redactSensitiveHeaders(headers)

        #expect(result == "[]")
    }

    @Test func redacts_aws_credential_headers() {
        var headers = HTTPFields()
        headers.append(HTTPField(name: HTTPField.Name("X-Amz-Security-Token")!, value: "aws-token"))
        headers.append(HTTPField(name: HTTPField.Name("X-Amz-Credential")!, value: "aws-cred"))

        let result = VerboseLoggingMiddleware.redactSensitiveHeaders(headers)

        #expect(!result.contains("aws-token"))
        #expect(!result.contains("aws-cred"))
        #expect(result.contains("[REDACTED]"))
    }

    @Test func intercept_passes_through_request_and_response() async throws {
        let subject = VerboseLoggingMiddleware()
        let url = URL(string: "https://test.tuist.dev")!
        var request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/test")
        request.headerFields[.authorization] = "Bearer secret"
        let response = HTTPResponse(status: 200)

        let (gotResponse, _) = try await subject.intercept(
            request,
            body: nil,
            baseURL: url,
            operationID: "test-op"
        ) { req, body, _ in
            #expect(req.headerFields[.authorization] == "Bearer secret")
            return (response, body)
        }

        #expect(gotResponse.status == response.status)
    }
}
