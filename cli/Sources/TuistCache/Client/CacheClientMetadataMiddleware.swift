import Foundation
import HTTPTypes
import OpenAPIRuntime
import TuistCore

struct CacheClientMetadataMiddleware: ClientMiddleware {
    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID _: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request

        if let runIdFieldName = HTTPField.Name("x-tuist-run-id") {
            request.headerFields.append(.init(name: runIdFieldName, value: RunMetadataStorage.current.runId))
        }

        return try await next(request, body, baseURL)
    }
}
