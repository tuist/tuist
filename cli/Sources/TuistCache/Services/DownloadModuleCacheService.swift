import Foundation
import Mockable
import OpenAPIRuntime
import OpenAPIURLSession
import TuistHTTP
import TuistServer

@Mockable
public protocol DownloadModuleCacheServicing: Sendable {
    func downloadModuleCacheArtifact(
        accountHandle: String,
        projectHandle: String,
        hash: String,
        name: String,
        cacheCategory: String,
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws -> Data
}

public enum DownloadModuleCacheServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)
    case notFound(String)
    case badRequest(String)
    /// The server admitted no response stream for the read and asked for a retry. The
    /// artifact exists and the server is healthy, so this is distinct from a failure:
    /// it is worth retrying, and worth reporting to the user as congestion rather than
    /// as an outage.
    case rateLimited(String, retryAfterSeconds: Int?)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The module cache artifact could not be downloaded due to an unknown response of \(statusCode)."
        case let .rateLimited(message, retryAfterSeconds):
            guard let retryAfterSeconds else { return message }
            return "\(message) (retry after \(retryAfterSeconds)s)"
        case let .unauthorized(message),
             let .forbidden(message),
             let .notFound(message),
             let .badRequest(message):
            return message
        }
    }
}

public struct DownloadModuleCacheService: DownloadModuleCacheServicing {
    public init() {}

    public func downloadModuleCacheArtifact(
        accountHandle: String,
        projectHandle: String,
        hash: String,
        name: String,
        cacheCategory: String,
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws -> Data {
        let client = Client.authenticated(
            cacheURL: serverURL,
            authenticationURL: authenticationURL,
            serverAuthenticationController: serverAuthenticationController,
            fullHandle: "\(accountHandle)/\(projectHandle)"
        )

        let response = try await client.downloadModuleCacheArtifact(
            .init(
                path: .init(id: hash),
                query: .init(
                    account_handle: accountHandle,
                    project_handle: projectHandle,
                    hash: hash,
                    name: name,
                    cache_category: cacheCategory
                )
            )
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .binary(body):
                return try await Data(collecting: body, upTo: .max)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw DownloadModuleCacheServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw DownloadModuleCacheServiceError.forbidden(error.message)
            }
        case let .code402(paymentRequired):
            switch paymentRequired.body {
            case let .json(error):
                throw DownloadModuleCacheServiceError.badRequest(error.message)
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw DownloadModuleCacheServiceError.notFound(error.message)
            }
        case let .unprocessableContent(unprocessableContent):
            switch unprocessableContent.body {
            case let .json(error):
                throw DownloadModuleCacheServiceError.badRequest(error.message)
            }
        case let .tooManyRequests(tooManyRequests):
            switch tooManyRequests.body {
            case let .json(error):
                throw DownloadModuleCacheServiceError.rateLimited(
                    error.message,
                    retryAfterSeconds: tooManyRequests.headers.retry_hyphen_after.flatMap(Int.init)
                )
            }
        // Neither service sends a `Range`, so a ranged answer is not a reply to
        // the request that was made. Its body is a fragment, and returning it
        // as the artifact would store a truncated one under a key that claims
        // to be whole, so it is refused. Declared on the operation because kura
        // honours ranges on this route; used by resume, which works below this
        // layer on the raw response.
        case .partialContent:
            throw DownloadModuleCacheServiceError.unknownError(206)
        case .rangeNotSatisfiable:
            throw DownloadModuleCacheServiceError.unknownError(416)
        case let .undocumented(statusCode: statusCode, _):
            throw DownloadModuleCacheServiceError.unknownError(statusCode)
        }
    }
}
