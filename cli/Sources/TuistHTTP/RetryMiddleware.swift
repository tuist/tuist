import Foundation
import HTTPTypes
import OpenAPIRuntime
import TuistLogging

public struct RetryMiddleware: ClientMiddleware {
    private let retryPolicy: HTTPRetryPolicy

    public init(
        maxRetries: Int? = nil,
        baseDelayMilliseconds: UInt64? = nil
    ) {
        retryPolicy = HTTPRetryPolicy(
            maximumRetryCount: maxRetries,
            baseDelayMilliseconds: baseDelayMilliseconds
        )
    }

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID _: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let bodyData: Data?
        if let body {
            bodyData = try await Data(collecting: body, upTo: .max)
        } else {
            bodyData = nil
        }

        for retry in 0 ..< retryPolicy.maximumRetryCount {
            let replayBody = bodyData.map { HTTPBody($0) }
            do {
                let (response, responseBody) = try await next(request, replayBody, baseURL)
                guard Self.isRetryableStatusCode(response.status.code) else {
                    return (response, responseBody)
                }
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
            try await Task<Never, Never>.sleep(nanoseconds: retryPolicy.delay(for: retry))
        }

        try Task<Never, Never>.checkCancellation()
        let replayBody = bodyData.map { HTTPBody($0) }
        return try await next(request, replayBody, baseURL)
    }

    private static func isRetryableStatusCode(_ statusCode: Int) -> Bool {
        statusCode == 408 || statusCode == 429 || (500 ..< 600).contains(statusCode)
    }
}
