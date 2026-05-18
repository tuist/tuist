import Foundation
import HTTPTypes
import OpenAPIRuntime

/// A middleware that adds a unique request ID header to every request.
public struct RequestIdMiddleware: ClientMiddleware {
    public init() {}

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID _: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        request.addRequestIDHeader()
        return try await next(request, body, baseURL)
    }
}
