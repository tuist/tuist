import Foundation
import HTTPTypes
import OpenAPIRuntime
import TuistHTTP
import TuistServer

struct CacheClientAuthenticationMiddleware: ClientMiddleware {
    private let authenticationURL: URL
    private let serverAuthenticationController: ServerAuthenticationControlling

    init(authenticationURL: URL, serverAuthenticationController: ServerAuthenticationControlling) {
        self.authenticationURL = authenticationURL
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

        guard let token = try await serverAuthenticationController.authenticationToken(serverURL: authenticationURL) else {
            throw ClientAuthenticationError.notAuthenticated
        }

        request.headerFields.append(
            .init(
                name: .authorization, value: "Bearer \(token.value)"
            )
        )

        return try await next(request, body, baseURL)
    }
}
