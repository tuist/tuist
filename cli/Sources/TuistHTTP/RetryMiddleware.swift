import Foundation
import HTTPTypes
import OpenAPIRuntime
import TuistLogging

public struct RetryMiddleware: ClientMiddleware {
    private let maxRetries: Int
    private static let retryableStatusCodes: Set<Int> = [429, 500, 502, 503, 504]

    public init(maxRetries: Int = 3) {
        self.maxRetries = maxRetries
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

        for retry in 0 ..< maxRetries {
            let replayBody = bodyData.map { HTTPBody($0) }
            do {
                let (response, responseBody) = try await next(request, replayBody, baseURL)
                guard Self.retryableStatusCodes.contains(response.status.code) else {
                    return (response, responseBody)
                }
                Logger.current.debug(
                    "Received HTTP \(response.status.code) for \(request.method.rawValue) \(request.path ?? ""), retrying (\(retry + 1)/\(maxRetries))..."
                )
            } catch {
                Logger.current.debug(
                    "HTTP request failed for \(request.method.rawValue) \(request.path ?? ""): \(error.localizedDescription), retrying (\(retry + 1)/\(maxRetries))..."
                )
            }
            try await Task<Never, Never>.sleep(nanoseconds: delay(for: retry))
        }

        try Task<Never, Never>.checkCancellation()
        let replayBody = bodyData.map { HTTPBody($0) }
        return try await next(request, replayBody, baseURL)
    }

    private func delay(for retry: Int) -> UInt64 {
        let baseInterval = TimeInterval(1_000_000)
        let randomInterval = Double.random(in: -1_000_000 ... 1_000_000)
        return UInt64(baseInterval * pow(2, Double(retry)) + randomInterval)
    }
}
