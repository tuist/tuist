import Foundation
import HTTPTypes
import OpenAPIRuntime
import TuistLogging

public struct RetryMiddleware: ClientMiddleware {
    private let retryPolicy: HTTPRetryPolicy
    private let retryableRequestMethods: Set<String>?
    private let retriesTransportErrors: Bool

    /// - Parameters:
    ///   - retriesTransportErrors: When `true` (the default) a thrown transport error,
    ///     including a timeout, is retried. Callers on a fail-fast path, such as the CAS
    ///     downloads that rely on the short `.tuistCAS` timeout to reach the circuit breaker
    ///     quickly, pass `false` so a hung backend surfaces immediately. Retryable HTTP
    ///     responses such as 503 are retried regardless of this flag.
    public init(
        maxRetries: Int? = nil,
        baseDelayMilliseconds: UInt64? = nil,
        retryableRequestMethods: Set<String>? = nil,
        retriesTransportErrors: Bool = true
    ) {
        retryPolicy = HTTPRetryPolicy(
            maximumRetryCount: maxRetries,
            baseDelayMilliseconds: baseDelayMilliseconds
        )
        self.retryableRequestMethods = retryableRequestMethods
        self.retriesTransportErrors = retriesTransportErrors
    }

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID _: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        if let retryableRequestMethods,
           !retryableRequestMethods.contains(request.method.rawValue)
        {
            return try await next(request, body, baseURL)
        }

        let bodyData: Data?
        if let body {
            bodyData = try await Data(collecting: body, upTo: .max)
        } else {
            bodyData = nil
        }

        for retry in 0 ..< retryPolicy.maximumRetryCount {
            let replayBody = bodyData.map { HTTPBody($0) }
            var delay = retryPolicy.delay(for: retry)
            do {
                let (response, responseBody) = try await next(request, replayBody, baseURL)
                guard Self.isRetryableStatusCode(response.status.code) else {
                    return (response, responseBody)
                }
                delay = Self.retryDelay(for: response, policyDelay: delay)
                Logger.current.debug(
                    "Received HTTP \(response.status.code) for \(request.method.rawValue) \(request.path ?? ""), retrying (\(retry + 1)/\(retryPolicy.maximumRetryCount))..."
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if !retriesTransportErrors {
                    throw error
                }
                Logger.current.debug(
                    "HTTP request failed for \(request.method.rawValue) \(request.path ?? ""): \(error.localizedDescription), retrying (\(retry + 1)/\(retryPolicy.maximumRetryCount))..."
                )
            }
            try await Task<Never, Never>.sleep(nanoseconds: delay)
        }

        try Task<Never, Never>.checkCancellation()
        let replayBody = bodyData.map { HTTPBody($0) }
        return try await next(request, replayBody, baseURL)
    }

    private static func isRetryableStatusCode(_ statusCode: Int) -> Bool {
        statusCode == 408 || statusCode == 429 || (500 ..< 600).contains(statusCode)
    }

    static func retryDelay(for response: HTTPResponse, policyDelay: UInt64) -> UInt64 {
        let retryAfterName = HTTPField.Name("Retry-After")!
        guard let value = response.headerFields[retryAfterName],
              let seconds = UInt64(value.trimmingCharacters(in: .whitespaces))
        else {
            return policyDelay
        }
        let milliseconds = seconds.multipliedReportingOverflow(by: 1000)
        let boundedMilliseconds = milliseconds.overflow
            ? HTTPRetryPolicy.maximumDelayMilliseconds
            : min(milliseconds.partialValue, HTTPRetryPolicy.maximumDelayMilliseconds)
        let retryAfter = boundedMilliseconds * 1_000_000
        guard retryAfter > 0 else { return policyDelay }
        return max(policyDelay, retryAfter + jitter(onTopOf: retryAfter))
    }

    /// `Retry-After` is a floor expressed in whole seconds, so without a smear across the
    /// second it names every client the server shed at once wakes on the same instant.
    private static func jitter(onTopOf retryAfter: UInt64) -> UInt64 {
        let maximumDelay = HTTPRetryPolicy.maximumDelayMilliseconds * 1_000_000
        let span = min(retryAfterResolutionNanoseconds, maximumDelay - retryAfter)
        guard span > 0 else { return 0 }
        return UInt64.random(in: 0 ... span)
    }

    private static let retryAfterResolutionNanoseconds: UInt64 = 1_000_000_000
}
