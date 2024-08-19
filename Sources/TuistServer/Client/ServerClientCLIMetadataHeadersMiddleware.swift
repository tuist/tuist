import Foundation
import OpenAPIRuntime
import TuistSupport

/// This middleware includes the release date of the CLI in the headers so that we can show
/// warnings if the on-premise installation is too old.
struct ServerClientCLIMetadataHeadersMiddleware: ClientMiddleware {
    let releaseDate = "2024.08.19"

    func intercept(
        _ request: Request,
        baseURL: URL,
        operationID _: String,
        next: (Request, URL) async throws -> Response
    ) async throws -> Response {
        var request = request
        request.headerFields.append(.init(name: "x-tuist-cli-release-date", value: releaseDate))
        request.headerFields.append(.init(name: "x-tuist-cli-version", value: Constants.version))
        return try await next(request, baseURL)
    }
}
