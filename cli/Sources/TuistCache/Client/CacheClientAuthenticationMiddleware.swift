import Foundation
import HTTPTypes
import OpenAPIRuntime
import TuistHTTP
import TuistServer

struct CacheClientAuthenticationMiddleware: ClientMiddleware {
    private let authenticationURL: URL
    private let serverAuthenticationController: ServerAuthenticationControlling
    private let cacheTokenStore: CacheTokenStoring
    private let projectHandle: String?

    init(
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling,
        cacheTokenStore: CacheTokenStoring,
        projectHandle: String?
    ) {
        self.authenticationURL = authenticationURL
        self.serverAuthenticationController = serverAuthenticationController
        self.cacheTokenStore = cacheTokenStore
        self.projectHandle = projectHandle
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

        // Prefer a token the cache node can verify itself, falling back to the
        // credential we already hold when the server cannot mint one.
        //
        // Only callers that name the project they are caching for take this
        // path. The scope is what keeps the token small enough to send as a
        // header, so exchanging without one would risk a token carrying every
        // project an account-wide credential reaches.
        var value = token.value
        if let projectHandle,
           let cacheToken = await cacheTokenStore.cacheToken(
               authenticationURL: authenticationURL,
               projectHandle: projectHandle
           )
        {
            value = cacheToken
        }

        request.headerFields.append(
            .init(
                name: .authorization, value: "Bearer \(value)"
            )
        )

        return try await next(request, body, baseURL)
    }
}
