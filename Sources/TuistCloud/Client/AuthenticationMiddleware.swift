import Foundation
import OpenAPIRuntime
import TuistSupport

enum AuthenticationError: FatalError {
    case notAuthenticated

    var type: ErrorType {
        switch self {
        case .notAuthenticated:
            return .abort
        }
    }

    var description: String {
        switch self {
        case .notAuthenticated:
            return "No cloud authentication token found. Authenticate by running `tuist cloud auth`."
        }
    }
}

/// Injects an authorization header to every request.
struct AuthenticationMiddleware: ClientMiddleware {
    func intercept(
        _ request: Request,
        baseURL: URL,
        operationID _: String,
        next: (Request, URL) async throws -> Response
    ) async throws -> Response {
        var request = request
        guard let token = try CloudAuthenticationController().authenticationToken(serverURL: baseURL)
        else {
            throw AuthenticationError.notAuthenticated
        }

        request.headerFields.append(.init(
            name: "Authorization", value: "Bearer \(token)"
        ))
        return try await next(request, baseURL)
    }
}
