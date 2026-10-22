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
    private let networkTrustedReports: Bool
    private let networkTrustedPublishing: Bool

    init(
        authenticationURL: URL? = nil, networkTrustedReports: Bool = false,
        networkTrustedPublishing: Bool = false
    ) {
        self.init(
            serverAuthenticationController: ServerAuthenticationController(),
            authenticationURL: authenticationURL,
            networkTrustedReports: networkTrustedReports,
            networkTrustedPublishing: networkTrustedPublishing
        )
    }

    init(
        serverAuthenticationController: ServerAuthenticationControlling,
        authenticationURL: URL? = nil,
        networkTrustedReports: Bool = false,
        networkTrustedPublishing: Bool = false
    ) {
        self.serverAuthenticationController = serverAuthenticationController
        self.authenticationURL = authenticationURL
        self.networkTrustedReports = networkTrustedReports
        self.networkTrustedPublishing = networkTrustedPublishing
    }

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request

        let urlForAuthentication = authenticationURL ?? baseURL
        let config = ServerAuthenticationConfig.current
        let reportOperation = networkTrustedReports &&
            ["createBuild", "createBuild (2)", "createTest"].contains(operationID)

        let token: AuthenticationToken?
        do {
            token = try await ServerAuthenticationConfig.$current.withValue(
                .init(
                    backgroundRefresh: reportOperation ? false : config.backgroundRefresh,
                    optionalAuthentication: config.optionalAuthentication
                )
            ) {
                try await serverAuthenticationController.authenticationToken(
                    serverURL: urlForAuthentication,
                    refreshIfNeeded: true
                )
            }
        } catch {
            if config.optionalAuthentication, !reportOperation {
                return try await next(request, body, baseURL)
            }
            throw error
        }

        guard let token else {
            if reportOperation, networkTrustedPublishing {
                try ServerReportPublishingMode.validateDestination(baseURL)
                return try await next(request, body, baseURL)
            }
            if config.optionalAuthentication, !reportOperation {
                return try await next(request, body, baseURL)
            }
            throw ClientAuthenticationError.notAuthenticated
        }
        if reportOperation, token.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ServerReportPublishingError.invalidCredentials
        }
        addAuthorizationHeader(to: &request, token: token)

        return try await next(request, body, baseURL)
    }

    private func addAuthorizationHeader(to request: inout HTTPRequest, token: AuthenticationToken) {
        request.headerFields[.authorization] = "Bearer \(token.value)"
    }
}
