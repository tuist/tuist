import Foundation
import HTTPTypes
import OpenAPIRuntime
import TuistHTTP
import TuistServer

struct CacheClientAuthenticationMiddleware: ClientMiddleware {
    private let credentialProvider: CacheCredentialProvider

    init(
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling,
        cacheTokenStore: CacheTokenStoring,
        fullHandle: String?
    ) {
        credentialProvider = CacheCredentialProvider(
            authenticationURL: authenticationURL,
            fullHandle: fullHandle,
            serverAuthenticationController: serverAuthenticationController,
            cacheTokenStore: cacheTokenStore
        )
    }

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID _: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request

        guard let credential = try await credentialProvider.credential() else {
            throw ClientAuthenticationError.notAuthenticated
        }

        request.headerFields.append(
            .init(
                name: .authorization, value: "Bearer \(credential)"
            )
        )

        return try await next(request, body, baseURL)
    }
}
