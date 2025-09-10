import Foundation
import HTTPTypes
import OpenAPIRuntime
#if canImport(TuistSupport)
    import TuistSupport
#endif

struct ServerDeleteCredentialsOnUnauthorizedMiddleware: ClientMiddleware {
    private let serverAuthenticationController: ServerAuthenticationControlling

    init(serverAuthenticationController: ServerAuthenticationControlling = ServerAuthenticationController()) {
        self.serverAuthenticationController = serverAuthenticationController
    }

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID _: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let (response, body) = try await next(request, body, baseURL)

        if response.status == .unauthorized {
            Logger.current.debug("""
            Deleting credentials after receiving an unauthorized response from the server:
              - Method: \(request.method.rawValue)
              - URL: \(baseURL.absoluteString)
              - Path: \(request.path ?? "")
              - Headers: \(request.headerFields)
            """)
            try await serverAuthenticationController.deleteCredentials(serverURL: baseURL)
        }

        return (response, body)
    }
}
