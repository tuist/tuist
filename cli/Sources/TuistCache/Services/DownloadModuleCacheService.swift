import Crypto
import Foundation
import Mockable
import OpenAPIRuntime
import OpenAPIURLSession
import TuistHTTP
import TuistLogging
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

public enum DownloadModuleCacheServiceError: LocalizedError, Equatable {
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
    /// The body did not match the digest its uploader declared, on two fetches in a
    /// row. A damaged copy at rest does not repair on retry, so this is a miss to
    /// rebuild from source rather than a transient failure.
    case checksumMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The module cache artifact could not be downloaded due to an unknown response of \(statusCode)."
        case let .rateLimited(message, retryAfterSeconds):
            guard let retryAfterSeconds else { return message }
            return "\(message) (retry after \(retryAfterSeconds)s)"
        case let .checksumMismatch(expected, actual):
            return "The downloaded module cache artifact does not match the checksum it was uploaded with (expected \(expected), received \(actual))."
        case let .unauthorized(message),
             let .forbidden(message),
             let .notFound(message),
             let .badRequest(message):
            return message
        }
    }
}

extension DownloadModuleCacheServiceError: HTTPStatusCodeError {
    public var httpStatusCode: Int {
        switch self {
        case let .unknownError(statusCode): return statusCode
        case .unauthorized: return 401
        case .forbidden: return 403
        case .notFound: return 404
        case .badRequest: return 400
        case .rateLimited: return 429
        case .checksumMismatch: return 422
        }
    }
}

public struct DownloadModuleCacheService: DownloadModuleCacheServicing {
    private let session: @Sendable () -> URLSession
    private let admission: TransferAdmission

    public init() {
        self.init(session: { .tuistArtifactDownload }, admission: .artifactDownloads)
    }

    init(session: @escaping @Sendable () -> URLSession, admission: TransferAdmission) {
        self.session = session
        self.admission = admission
    }

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
            session: session(),
            fullHandle: "\(accountHandle)/\(projectHandle)"
        )
        // Admitted until the whole body is in, resumes included.
        let fetch = {
            try await admission.run {
                try await fetchArtifact(
                    client: client,
                    accountHandle: accountHandle,
                    projectHandle: projectHandle,
                    hash: hash,
                    name: name,
                    cacheCategory: cacheCategory
                )
            }
        }

        let first = try await fetch()
        guard let mismatch = first.checksumMismatch else { return first.data }
        // Damage in flight is transient and damage at rest is not, so one fresh
        // fetch tells them apart. It compares against its own response's digest, in
        // case the artifact was replaced in between.
        Logger.current.debug(
            "The downloaded module cache artifact \(name) with hash \(hash) did not match its checksum. Downloading it again..."
        )
        let second = try await fetch()
        guard second.checksumMismatch == nil else { throw second.checksumMismatch ?? mismatch }
        return second.data
    }

    private struct FetchedArtifact {
        let data: Data
        /// Set when the response declared a digest the body does not match. A
        /// response without one is not compared, as before.
        let checksumMismatch: DownloadModuleCacheServiceError?
    }

    private func fetchArtifact(
        client: Client,
        accountHandle: String,
        projectHandle: String,
        hash: String,
        name: String,
        cacheCategory: String
    ) async throws -> FetchedArtifact {
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
                let data = try await Data(collecting: body, upTo: .max)
                return FetchedArtifact(
                    data: data,
                    checksumMismatch: Self.checksumMismatch(
                        of: data,
                        declared: okResponse.headers.tuist_hyphen_checksum_hyphen_sha256
                    )
                )
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

    static func checksumMismatch(of data: Data, declared: String?) -> DownloadModuleCacheServiceError? {
        guard let declared = declared?.lowercased(), !declared.isEmpty else { return nil }
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual != declared else { return nil }
        return .checksumMismatch(expected: declared, actual: actual)
    }
}
