import Foundation
import HTTPTypes
import OpenAPIRuntime
import TuistSupport

/// A middleware that gets any warning returned in a "x-cloud-warning" header
/// and outputs it to the user.
struct ServerClientRequestIdMiddleware: ClientMiddleware {
    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID _: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        guard let httpFieldName = HTTPField.Name("x-request-id") else { return try await next(request, body, baseURL) }
        request.headerFields.append(.init(name: httpFieldName, value: UUID().uuidString))
        return try await next(request, body, baseURL)
    }
}
