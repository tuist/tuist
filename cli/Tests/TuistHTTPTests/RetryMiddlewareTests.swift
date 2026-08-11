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

    @Test(arguments: [408, 429, 500, 502, 503, 504, 525])
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

    @Test func does_not_retry_a_request_method_outside_the_allowlist() async throws {
        let subject = RetryMiddleware(
            maxRetries: 3,
            retryableRequestMethods: ["GET"]
        )
        var callCount = 0

        let (response, _) = try await subject.intercept(
            HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/test"),
            body: HTTPBody(Data("body".utf8)),
            baseURL: URL(string: "https://test.tuist.dev")!,
            operationID: "test-op"
        ) { _, body, _ in
            callCount += 1
            #expect(body != nil)
            return (HTTPResponse(status: 503), nil)
        }

        #expect(response.status.code == 503)
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

    @Test func does_not_retry_thrown_errors_when_transport_retries_are_disabled() async throws {
        struct TestError: Error {}
        let subject = RetryMiddleware(maxRetries: 3, retriesTransportErrors: false)
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

        #expect(callCount == 1)
    }

    @Test func still_retries_retryable_status_codes_when_transport_retries_are_disabled() async throws {
        let subject = RetryMiddleware(maxRetries: 2, retriesTransportErrors: false)
        var callCount = 0

        let (response, _) = try await subject.intercept(
            HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/test"),
            body: nil,
            baseURL: URL(string: "https://test.tuist.dev")!,
            operationID: "test-op"
        ) { _, _, _ in
            callCount += 1
            if callCount == 1 {
                return (HTTPResponse(status: 503), nil)
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

    @Test func uses_numeric_retry_after_when_it_exceeds_the_policy_delay() {
        var response = HTTPResponse(status: 503)
        response.headerFields[HTTPField.Name("Retry-After")!] = "1"

        #expect(
            RetryMiddleware.retryDelay(for: response, policyDelay: 100_000_000)
                == 1_000_000_000
        )
    }

    @Test func bounds_numeric_retry_after_to_the_maximum_policy_delay() {
        var response = HTTPResponse(status: 503)
        response.headerFields[HTTPField.Name("Retry-After")!] = "120"

        #expect(
            RetryMiddleware.retryDelay(for: response, policyDelay: 100_000_000)
                == HTTPRetryPolicy.maximumDelayMilliseconds * 1_000_000
        )
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

    @Test func does_not_retry_on_cancellation() async throws {
        let subject = RetryMiddleware(maxRetries: 3)
        var callCount = 0

        await #expect(throws: CancellationError.self) {
            try await subject.intercept(
                HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/test"),
                body: nil,
                baseURL: URL(string: "https://test.tuist.dev")!,
                operationID: "test-op"
            ) { _, _, _ in
                callCount += 1
                throw CancellationError()
            }
        }

        #expect(callCount == 1)
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
