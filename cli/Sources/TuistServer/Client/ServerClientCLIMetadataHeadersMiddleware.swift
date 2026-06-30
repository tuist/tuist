import Foundation
import HTTPTypes
import OpenAPIRuntime
#if canImport(TuistSupport)
    import TuistConstants
    import TuistSupport
#endif

/// This middleware includes the release date of the CLI in the headers so that we can show
/// warnings if the on-premise installation is too old.
struct ServerClientCLIMetadataHeadersMiddleware: ClientMiddleware {
    let releaseDate = "2024.09.26"
    static let localDevelopmentVersion = "4.202.0-canary.21"

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID _: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request

        guard let cliReleaseDateName = HTTPField.Name("x-tuist-cli-release-date"),
              let cliVersionName = HTTPField.Name("x-tuist-cli-version")
        else { return try await next(request, body, baseURL) }

        request.headerFields.append(.init(name: cliReleaseDateName, value: releaseDate))
        #if canImport(TuistSupport)
            let cliVersion =
                Constants.version == "x.y.z" ? Self.localDevelopmentVersion : Constants.version!
            request.headerFields.append(.init(name: cliVersionName, value: cliVersion))
        #endif
        return try await next(request, body, baseURL)
    }
}
