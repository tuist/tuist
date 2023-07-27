import OpenAPIRuntime
import Foundation
import TuistSupport

/// Injects an authorization header to every request.
struct AuthenticationMiddleware: ClientMiddleware {
    func intercept(
        _ request: Request,
        baseURL: URL,
        operationID: String,
        next: (Request, URL) async throws -> Response
    ) async throws -> Response {
        var request = request
        let environment = ProcessInfo.processInfo.environment
        let tokenFromEnvironment = environment[Constants.EnvironmentVariables.cloudToken]
        let token: String?
        if CIChecker().isCI() {
            token = tokenFromEnvironment
        } else {
            token = try? tokenFromEnvironment ?? CredentialsStore().read(serverURL: baseURL)?.token
        }

        if let token = token {
            request.headerFields.append(.init(
                name: "Authorization", value: "Bearer \(token)"
            ))
        } else {
            try CloudSessionController().authenticate(serverURL: baseURL)
            // TODO: Fix
        }
        return try await next(request, baseURL)
    }
}
