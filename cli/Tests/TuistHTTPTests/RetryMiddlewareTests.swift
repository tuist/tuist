import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing

@testable import TuistHTTP

struct RetryMiddlewareTests {
    @Test func does_not_retry_on_success() async throws {
        let subject = RetryMiddleware(maxRetries: 3)
        var callCount = 0

        let (response, _) = try await subject.intercept(
            HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/test"),
            body: nil,
            baseURL: URL(string: "https://test.tuist.dev")!,
            operationID: "test-op"
        ) { _, _, _ in
            callCount += 1
            return (HTTPResponse(status: 200), nil)
        }

        #expect(response.status.code == 200)
        #expect(callCount == 1)
    }

    @Test(arguments: [429, 500, 502, 503, 504])
    func retries_on_retryable_status_code(statusCode: Int) async throws {
        let subject = RetryMiddleware(maxRetries: 2)
        var callCount = 0

        let (response, _) = try await subject.intercept(
            HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/test"),
            body: nil,
            baseURL: URL(string: "https://test.tuist.dev")!,
            operationID: "test-op"
        ) { _, _, _ in
            callCount += 1
            if callCount == 1 {
                return (HTTPResponse(status: .init(code: statusCode)), nil)
            }
            return (HTTPResponse(status: 200), nil)
        }

        #expect(response.status.code == 200)
        #expect(callCount == 2)
    }

    @Test(arguments: [400, 401, 403, 404, 422])
    func does_not_retry_on_non_retryable_status_code(statusCode: Int) async throws {
        let subject = RetryMiddleware(maxRetries: 3)
        var callCount = 0

        let (response, _) = try await subject.intercept(
            HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/test"),
            body: nil,
            baseURL: URL(string: "https://test.tuist.dev")!,
            operationID: "test-op"
        ) { _, _, _ in
            callCount += 1
            return (HTTPResponse(status: .init(code: statusCode)), nil)
        }

        #expect(response.status.code == statusCode)
        #expect(callCount == 1)
    }

    @Test func retries_on_thrown_error() async throws {
        struct TestError: Error {}
        let subject = RetryMiddleware(maxRetries: 2)
        var callCount = 0

        let (response, _) = try await subject.intercept(
            HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/test"),
            body: nil,
            baseURL: URL(string: "https://test.tuist.dev")!,
            operationID: "test-op"
        ) { _, _, _ in
            callCount += 1
            if callCount == 1 {
                throw TestError()
            }
            return (HTTPResponse(status: 200), nil)
        }

        #expect(response.status.code == 200)
        #expect(callCount == 2)
    }

    @Test func returns_last_response_after_max_retries() async throws {
        let subject = RetryMiddleware(maxRetries: 2)
        var callCount = 0

        let (response, _) = try await subject.intercept(
            HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/test"),
            body: nil,
            baseURL: URL(string: "https://test.tuist.dev")!,
            operationID: "test-op"
        ) { _, _, _ in
            callCount += 1
            return (HTTPResponse(status: 502), nil)
        }

        #expect(response.status.code == 502)
        // 2 retries in loop + 1 final attempt
        #expect(callCount == 3)
    }

    @Test func throws_error_after_max_retries_exhausted() async throws {
        struct TestError: Error {}
        let subject = RetryMiddleware(maxRetries: 2)
        var callCount = 0

        await #expect(throws: TestError.self) {
            try await subject.intercept(
                HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/test"),
                body: nil,
                baseURL: URL(string: "https://test.tuist.dev")!,
                operationID: "test-op"
            ) { _, _, _ in
                callCount += 1
                throw TestError()
            }
        }

        // 2 retries in loop + 1 final attempt
        #expect(callCount == 3)
    }

    @Test func passes_nil_body_without_error() async throws {
        let subject = RetryMiddleware(maxRetries: 1)
        var receivedBody: HTTPBody?

        let (response, _) = try await subject.intercept(
            HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/test"),
            body: nil,
            baseURL: URL(string: "https://test.tuist.dev")!,
            operationID: "test-op"
        ) { _, body, _ in
            receivedBody = body
            return (HTTPResponse(status: 200), nil)
        }

        #expect(response.status.code == 200)
        #expect(receivedBody == nil)
    }

    @Test func replays_request_body_on_retries() async throws {
        let subject = RetryMiddleware(maxRetries: 2)
        let bodyContent = "test-body-content"
        var receivedBodies: [String] = []

        let (response, _) = try await subject.intercept(
            HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/test"),
            body: HTTPBody(bodyContent),
            baseURL: URL(string: "https://test.tuist.dev")!,
            operationID: "test-op"
        ) { _, body, _ in
            if let body {
                let data = try await Data(collecting: body, upTo: .max)
                receivedBodies.append(String(data: data, encoding: .utf8)!)
            }
            if receivedBodies.count == 1 {
                return (HTTPResponse(status: 502), nil)
            }
            return (HTTPResponse(status: 200), nil)
        }

        #expect(response.status.code == 200)
        #expect(receivedBodies == [bodyContent, bodyContent])
    }
}
