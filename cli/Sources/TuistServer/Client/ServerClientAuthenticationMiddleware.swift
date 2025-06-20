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
            return "You must be logged in to do this. To log in, run 'tuist auth login'."
        }
    }
}

/// Injects an authorization header to every request.
struct ServerClientAuthenticationMiddleware: ClientMiddleware {
    private let serverAuthenticationController: ServerAuthenticationControlling

    init() {
        self.init(
            serverAuthenticationController: ServerAuthenticationController(),
        )
    }

    init(
        serverAuthenticationController: ServerAuthenticationControlling,
    ) {
        self.serverAuthenticationController = serverAuthenticationController
    }

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID _: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request

        guard let token = try await serverAuthenticationController.authenticationToken(
            serverURL: baseURL
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
