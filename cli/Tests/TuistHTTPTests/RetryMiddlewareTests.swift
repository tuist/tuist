import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
import TuistEnvironmentTesting

@testable import TuistHTTP

struct RetryMiddlewareTests {
    @Test(arguments: [429, 503])
    func retries_unforwarded_cache_upload_with_intact_body(statusCode: Int) async throws {
        let subject = RetryMiddleware(
            maxRetries: 2, baseDelayMilliseconds: 0, retryableRequestMethods: ["GET"],
            retriesUnforwardedCacheRequests: true
        )
        var attempts = 0
        let (response, _) = try await subject.intercept(
            HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/upload"),
            body: HTTPBody(Data("artifact".utf8)),
            baseURL: URL(string: "https://account.cache.tuist.dev")!, operationID: "upload"
        ) { _, body, _ in
            attempts += 1
            let payload = try await Data(collecting: #require(body), upTo: .max)
            #expect(payload == Data("artifact".utf8))
            var response = HTTPResponse(status: attempts == 1 ? .init(code: statusCode) : .created)
            response.headerFields[HTTPField.Name("X-Tuist-Cache-Activation")!] = "pending"
            return (response, nil)
        }
        #expect(response.status == .created)
        #expect(attempts == 2)
    }

    @Test(arguments: ["", "pending"])
    func unforwarded_retry_requires_opt_in(marker: String) async throws {
        let subject = RetryMiddleware(maxRetries: 2, baseDelayMilliseconds: 0, retryableRequestMethods: ["GET"])
        var attempts = 0
        let (response, _) = try await subject.intercept(
            HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/upload"), body: nil,
            baseURL: URL(string: "https://account.cache.tuist.dev")!, operationID: "upload"
        ) { _, _, _ in
            attempts += 1
            var response = HTTPResponse(status: .serviceUnavailable)
            response.headerFields[HTTPField.Name("X-Tuist-Cache-Activation")!] = marker
            return (response, nil)
        }
        #expect(response.status == .serviceUnavailable)
        #expect(attempts == 1)
    }

    @Test(arguments: [false, true])
    func unforwarded_retry_does_not_replay_single_pass_or_committed_upload(singlePass: Bool) async throws {
        let subject = RetryMiddleware(
            maxRetries: 2, baseDelayMilliseconds: 0, retryableRequestMethods: ["GET"],
            retriesUnforwardedCacheRequests: true
        )
        let stream = AsyncStream<ArraySlice<UInt8>> { continuation in
            continuation.yield(ArraySlice("artifact".utf8))
            continuation.finish()
        }
        let body = singlePass ? HTTPBody(stream, length: .unknown) : HTTPBody(Data("artifact".utf8))
        var attempts = 0
        _ = try await subject.intercept(
            HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/upload"), body: body,
            baseURL: URL(string: "https://account.cache.tuist.dev")!, operationID: "upload"
        ) { _, body, _ in
            attempts += 1
            _ = try await Data(collecting: #require(body), upTo: .max)
            var response = HTTPResponse(status: .serviceUnavailable)
            if singlePass { response.headerFields[HTTPField.Name("X-Tuist-Cache-Activation")!] = "pending" }
            return (response, nil)
        }
        #expect(attempts == 1)
    }

    @Test func unforwarded_retry_is_bounded() async throws {
        let subject = RetryMiddleware(
            maxRetries: 2, baseDelayMilliseconds: 0, retryableRequestMethods: ["GET"],
            retriesUnforwardedCacheRequests: true
        )
        var attempts = 0
        let (response, _) = try await subject.intercept(
            HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/upload"), body: nil,
            baseURL: URL(string: "https://account.cache.tuist.dev")!, operationID: "upload"
        ) { _, _, _ in
            attempts += 1
            var response = HTTPResponse(status: .serviceUnavailable)
            response.headerFields[HTTPField.Name("X-Tuist-Cache-Activation")!] = "pending"
            return (response, nil)
        }
        #expect(response.status == .serviceUnavailable)
        #expect(attempts == 3)
    }

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

    @Test(.withMockedEnvironment())
    func recovers_by_default_when_the_first_four_attempts_fail() async throws {
        struct TestError: Error {}
        let subject = RetryMiddleware(baseDelayMilliseconds: 0)
        var callCount = 0

        let (response, _) = try await subject.intercept(
            HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/test"),
            body: nil,
            baseURL: URL(string: "https://test.tuist.dev")!,
            operationID: "test-op"
        ) { _, _, _ in
            callCount += 1
            switch callCount {
            case 1: throw TestError()
            case 2 ... 4: return (HTTPResponse(status: .badGateway), nil)
            default: return (HTTPResponse(status: 200), nil)
            }
        }

        #expect(response.status.code == 200)
        #expect(callCount == 5)
    }

    @Test func does_not_retry_a_throttled_authorization_denial() async throws {
        let subject = RetryMiddleware(maxRetries: 3)
        var callCount = 0

        await #expect(throws: AuthorizationThrottledError(retryAfterSeconds: 30)) {
            try await subject.intercept(
                HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/test"),
                body: nil,
                baseURL: URL(string: "https://test.tuist.dev")!,
                operationID: "test-op"
            ) { _, _, _ in
                callCount += 1
                var response = HTTPResponse(status: 429)
                response.headerFields[HTTPField.Name("x-tuist-throttle-reason")!] = "authorization"
                response.headerFields[HTTPField.Name("Retry-After")!] = "30"
                return (response, nil)
            }
        }

        #expect(callCount == 1)
    }

    @Test func retries_a_throttled_response_without_an_authorization_reason() async throws {
        let subject = RetryMiddleware(maxRetries: 2, baseDelayMilliseconds: 0)
        var callCount = 0

        let (response, _) = try await subject.intercept(
            HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/test"),
            body: nil,
            baseURL: URL(string: "https://test.tuist.dev")!,
            operationID: "test-op"
        ) { _, _, _ in
            callCount += 1
            if callCount == 1 {
                return (HTTPResponse(status: 429), nil)
            }
            return (HTTPResponse(status: 200), nil)
        }

        #expect(response.status.code == 200)
        #expect(callCount == 2)
    }

    @Test func does_not_retry_a_throttled_authorization_denial_outside_the_method_allowlist() async throws {
        let subject = RetryMiddleware(maxRetries: 3, retryableRequestMethods: ["GET"])
        var callCount = 0

        await #expect(throws: AuthorizationThrottledError(retryAfterSeconds: nil)) {
            try await subject.intercept(
                HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/test"),
                body: HTTPBody(Data("body".utf8)),
                baseURL: URL(string: "https://test.tuist.dev")!,
                operationID: "test-op"
            ) { _, _, _ in
                callCount += 1
                var response = HTTPResponse(status: 429)
                response.headerFields[HTTPField.Name("x-tuist-throttle-reason")!] = "authorization"
                return (response, nil)
            }
        }

        #expect(callCount == 1)
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

        let delay = RetryMiddleware.retryDelay(for: response, policyDelay: 100_000_000)

        #expect(delay >= 1_000_000_000)
        #expect(delay <= 2_000_000_000)
    }

    @Test func spreads_numeric_retry_after_across_clients() {
        var response = HTTPResponse(status: 503)
        response.headerFields[HTTPField.Name("Retry-After")!] = "1"

        let delays = Set(
            (0 ..< 64).map { _ in
                RetryMiddleware.retryDelay(for: response, policyDelay: 100_000_000)
            }
        )

        #expect(delays.count > 1)
        #expect(delays.allSatisfy { $0 >= 1_000_000_000 && $0 <= 2_000_000_000 })
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
                return (HTTPResponse(status: 503), nil)
            }
            return (HTTPResponse(status: 200), nil)
        }

        #expect(response.status.code == 200)
        #expect(receivedBodies == [bodyContent, bodyContent])
    }

    @Test(arguments: [502, 504])
    func does_not_replay_a_non_idempotent_operation_on_an_ambiguous_status(statusCode: Int) async throws {
        let attempts = try await Self.attempts(
            method: .post, operationID: "createCommandEvent", failures: [.status(statusCode)]
        )

        #expect(attempts == 1)
    }

    @Test(arguments: [URLError.Code.networkConnectionLost, .timedOut])
    func does_not_replay_a_non_idempotent_operation_after_a_transport_failure(code: URLError.Code) async throws {
        let attempts = try await Self.attempts(
            method: .post, operationID: "createProject", failures: [.transport(code)]
        )

        #expect(attempts == 1)
    }

    @Test(arguments: [
        ReplayFailure.transport(.cannotConnectToHost),
        .transport(.cannotFindHost),
        .transport(.dnsLookupFailed),
        .transport(.notConnectedToInternet),
        .transport(.secureConnectionFailed),
        .status(503),
        .status(429),
    ])
    func replays_a_non_idempotent_operation_the_server_never_processed(failure: ReplayFailure) async throws {
        let attempts = try await Self.attempts(
            method: .post, operationID: "createCommandEvent", failures: [failure]
        )

        #expect(attempts == 2)
    }

    @Test(arguments: [ReplayFailure.status(502), .transport(.networkConnectionLost), .transport(.timedOut)])
    func replays_a_get_request_after_an_ambiguous_failure(failure: ReplayFailure) async throws {
        let attempts = try await Self.attempts(method: .get, operationID: "listProjects", failures: [failure])

        #expect(attempts == 2)
    }

    @Test(arguments: [ReplayFailure.status(502), .transport(.networkConnectionLost)])
    func replays_an_idempotent_operation_after_an_ambiguous_failure(failure: ReplayFailure) async throws {
        let attempts = try await Self.attempts(
            method: .post,
            operationID: "generateBuildsMultipartUploadURL",
            failures: [failure],
            subject: RetryMiddleware(
                maxRetries: 4, baseDelayMilliseconds: 0, idempotentOperationIDs: ["generateBuildsMultipartUploadURL"]
            )
        )

        #expect(attempts == 2)
    }

    @Test(arguments: [
        CredentialFailure.transport(.networkConnectionLost),
        .transport(.cannotConnectToHost),
        .status(502),
        .status(401),
        .other,
    ])
    func never_replays_a_request_whose_credentials_could_not_be_obtained(failure: CredentialFailure) async throws {
        let (attempts, error) = await Self.credentialAttempts(failure: failure)

        #expect(attempts == 1)
        switch failure {
        case let .transport(code): #expect((error as? URLError)?.code == code)
        case let .status(code): #expect((error as? CredentialStatusError)?.httpStatusCode == code)
        case .other: #expect(error is CredentialStatusError.Other)
        }
    }

    enum CredentialFailure: Sendable, CustomTestStringConvertible {
        case transport(URLError.Code)
        case status(Int)
        case other

        var error: any Error {
            switch self {
            case let .transport(code): URLError(code)
            case let .status(code): CredentialStatusError(httpStatusCode: code)
            case .other: CredentialStatusError.Other()
            }
        }

        var testDescription: String {
            switch self {
            case let .transport(code): "URLError \(code.rawValue)"
            case let .status(code): "HTTP \(code)"
            case .other: "other"
            }
        }
    }

    struct CredentialStatusError: HTTPStatusCodeError, Equatable {
        struct Other: Error {}
        let httpStatusCode: Int
    }

    static func credentialAttempts(failure: CredentialFailure) async -> (attempts: Int, error: (any Error)?) {
        let subject = RetryMiddleware(maxRetries: 4, baseDelayMilliseconds: 0)
        var attempts = 0
        do {
            _ = try await subject.intercept(
                HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/test"),
                body: HTTPBody(Data("{}".utf8)),
                baseURL: URL(string: "https://test.tuist.dev")!,
                operationID: "createProject"
            ) { _, _, _ in
                attempts += 1
                guard attempts == 1 else { return (HTTPResponse(status: 200), nil) }
                throw ClientError(
                    operationID: "createProject",
                    operationInput: "",
                    request: nil,
                    requestBody: nil,
                    baseURL: nil,
                    response: nil,
                    responseBody: nil,
                    causeDescription: "Middleware threw an error.",
                    underlyingError: CredentialAcquisitionError(underlyingError: failure.error)
                )
            }
            return (attempts, nil)
        } catch {
            return (attempts, error)
        }
    }

    enum ReplayFailure: Sendable, CustomTestStringConvertible {
        case status(Int)
        case transport(URLError.Code)

        var testDescription: String {
            switch self {
            case let .status(code): "HTTP \(code)"
            case let .transport(code): "URLError \(code.rawValue)"
            }
        }
    }

    static func attempts(
        method: HTTPRequest.Method,
        operationID: String,
        failures: [ReplayFailure],
        subject: RetryMiddleware = RetryMiddleware(maxRetries: 4, baseDelayMilliseconds: 0)
    ) async throws -> Int {
        var attempts = 0
        _ = try? await subject.intercept(
            HTTPRequest(method: method, scheme: nil, authority: nil, path: "/test"),
            body: method == .get ? nil : HTTPBody(Data("{}".utf8)),
            baseURL: URL(string: "https://test.tuist.dev")!,
            operationID: operationID
        ) { _, _, _ in
            attempts += 1
            guard attempts <= failures.count else { return (HTTPResponse(status: 200), nil) }
            switch failures[attempts - 1] {
            case let .status(code):
                return (HTTPResponse(status: .init(code: code)), nil)
            case let .transport(code):
                throw ClientError(
                    operationID: operationID,
                    operationInput: "",
                    request: nil,
                    requestBody: nil,
                    baseURL: nil,
                    response: nil,
                    responseBody: nil,
                    causeDescription: "Transport threw an error.",
                    underlyingError: URLError(code)
                )
            }
        }
        return attempts
    }
}
