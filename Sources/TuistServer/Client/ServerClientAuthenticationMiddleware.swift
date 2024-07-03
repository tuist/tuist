import Foundation
import OpenAPIRuntime
import TuistSupport

public enum ServerClientAuthenticationError: FatalError {
    case notAuthenticated

    public var type: ErrorType {
        switch self {
        case .notAuthenticated:
            return .abort
        }
    }

    public var description: String {
        switch self {
        case .notAuthenticated:
            return "No Tuist authentication token found. Authenticate by running `tuist auth`."
        }
    }
}

/// Injects an authorization header to every request.
struct ServerClientAuthenticationMiddleware: ClientMiddleware {
    func intercept(
        _ request: Request,
        baseURL: URL,
        operationID _: String,
        next: (Request, URL) async throws -> Response
    ) async throws -> Response {
        var request = request
        guard let token = try ServerAuthenticationController().authenticationToken(serverURL: baseURL)
        else {
            throw ServerClientAuthenticationError.notAuthenticated
        }

        request.headerFields.append(.init(
            name: "Authorization", value: "Bearer \(token.value)"
        ))
        return try await next(request, baseURL)
    }
}
