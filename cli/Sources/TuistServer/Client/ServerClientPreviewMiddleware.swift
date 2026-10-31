import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Opts into desktop formats only on clients that tolerate unknown response types and platforms.
struct ServerClientPreviewMiddleware: ClientMiddleware {
    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        if ["getPreview", "listPreviews", "getLatestPreview", "completePreviewsMultipartUpload"].contains(operationID),
           let name = HTTPField.Name("x-tuist-preview-capabilities")
        {
            request.headerFields[name] = "desktop"
        }
        return try await next(request, body, baseURL)
    }
}
