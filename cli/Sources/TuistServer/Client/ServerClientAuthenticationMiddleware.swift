import Foundation
import HTTPTypes
import OpenAPIRuntime
import TuistHTTP

#if canImport(TuistSupport)
    import TuistSupport
#endif

/// Injects an authorization header to every request.
struct ServerClientAuthenticationMiddleware: ClientMiddleware {
    private let serverAuthenticationController: ServerAuthenticationControlling
    private let authenticationURL: URL?

    init(authenticationURL: URL? = nil) {
        self.init(
            serverAuthenticationController: ServerAuthenticationController(),
            authenticationURL: authenticationURL
        )
    }

    init(
        serverAuthenticationController: ServerAuthenticationControlling,
        authenticationURL: URL? = nil
    ) {
        self.serverAuthenticationController = serverAuthenticationController
        self.authenticationURL = authenticationURL
    }

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID _: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request

        let urlForAuthentication = authenticationURL ?? baseURL
        let config = ServerAuthenticationConfig.current

        let token: AuthenticationToken?
        do {
            token = try await serverAuthenticationController.authenticationToken(
                serverURL: urlForAuthentication,
                refreshIfNeeded: true
            )
        } catch {
            if config.optionalAuthentication {
                return try await next(request, body, baseURL)
            }
            throw error
        }

        guard let token else {
            if config.optionalAuthentication {
                return try await next(request, body, baseURL)
            }
            throw ClientAuthenticationError.notAuthenticated
        }
        addAuthorizationHeader(to: &request, token: token)

        return try await next(request, body, baseURL)
    }

    private func addAuthorizationHeader(to request: inout HTTPRequest, token: AuthenticationToken) {
        request.headerFields[.authorization] = "Bearer \(token.value)"
    }
}
