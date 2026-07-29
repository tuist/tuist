import Foundation
import HTTPTypes
import OpenAPIRuntime
import TuistLogging

public struct RetryMiddleware: ClientMiddleware {
    private let retryPolicy: HTTPRetryPolicy
    private let retryableRequestMethods: Set<String>?

    public init(
        maxRetries: Int? = nil,
        baseDelayMilliseconds: UInt64? = nil,
        retryableRequestMethods: Set<String>? = nil
    ) {
        retryPolicy = HTTPRetryPolicy(
            maximumRetryCount: maxRetries,
            baseDelayMilliseconds: baseDelayMilliseconds
        )
        self.retryableRequestMethods = retryableRequestMethods
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
        let milliseconds = seconds.multipliedReportingOverflow(by: 1_000)
        let boundedMilliseconds = milliseconds.overflow
            ? HTTPRetryPolicy.maximumDelayMilliseconds
            : min(milliseconds.partialValue, HTTPRetryPolicy.maximumDelayMilliseconds)
        return max(policyDelay, boundedMilliseconds * 1_000_000)
    }
}
