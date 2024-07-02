import Foundation
import OpenAPIRuntime
import TuistSupport

/// A middleware that gets any warning returned in a "x-cloud-warning" header
/// and outputs it to the user.
struct ServerClientRequestIdMiddleware: ClientMiddleware {
    func intercept(
        _ request: Request,
        baseURL: URL,
        operationID _: String,
        next: (Request, URL) async throws -> Response
    ) async throws -> Response {
        var request = request
        request.headerFields.append(.init(name: "x-request-id", value: UUID().uuidString))
        return try await next(request, baseURL)
    }
}
