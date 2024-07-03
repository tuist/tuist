import Foundation
import OpenAPIRuntime
import TuistSupport

/// A middleware that outputs in debug mode the request and responses sent and received from the server
struct ServerClientVerboseLoggingMiddleware: ClientMiddleware {
    func intercept(
        _ request: Request,
        baseURL: URL,
        operationID _: String,
        next: (Request, URL) async throws -> Response
    ) async throws -> Response {
        let requestJsonBody: Any? = if let body = request.body {
            try? JSONSerialization.jsonObject(with: body)
        } else {
            nil
        }

        logger.debug("""
        Sending HTTP request to Tuist:
          - Method: \(request.method.rawValue)
          - URL: \(baseURL.absoluteString)
          - Path: \(request.path)
          - Query: \(request.query ?? "")
          - Body: \(requestJsonBody ?? "")
          - Headers: \(request.headerFields)
        """)

        let response = try await next(request, baseURL)

        let responseJsonBody: Any? = try? JSONSerialization.jsonObject(with: response.body)

        logger.debug("""
        Received HTTP response from Tuist:
          - Status: \(response.statusCode)
          - Body: \(responseJsonBody ?? "")
          - Headers: \(response.headerFields)
        """)

        return response
    }
}
