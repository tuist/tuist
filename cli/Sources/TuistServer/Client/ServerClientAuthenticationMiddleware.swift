import Foundation
import HTTPTypes
import Logging
import OpenAPIRuntime

#if canImport(TuistSupport)
    import TuistSupport
#endif

public enum ServerClientAuthenticationError: LocalizedError, Equatable {
    case notAuthenticated

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be logged in to do this."
        }
    }
}

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
        guard let token = try await serverAuthenticationController.authenticationToken(
            serverURL: urlForAuthentication
        )
        else {
            throw ServerClientAuthenticationError.notAuthenticated
        }
        request.headerFields.append(
            .init(
                name: .authorization, value: "Bearer \(token.value)"
            )
        )
        return try await next(request, body, baseURL)
    }
}
