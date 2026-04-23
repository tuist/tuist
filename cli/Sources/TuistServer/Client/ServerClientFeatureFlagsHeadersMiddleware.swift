import Foundation
import HTTPTypes
import OpenAPIRuntime

struct ServerClientFeatureFlagsHeadersMiddleware: ClientMiddleware {
    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID _: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request

        if let headerValue = ClientFeatureFlags.headerValue(),
           let headerName = HTTPField.Name(ClientFeatureFlags.headerName)
        {
            request.headerFields[headerName] = headerValue
        }

        return try await next(request, body, baseURL)
    }
}
