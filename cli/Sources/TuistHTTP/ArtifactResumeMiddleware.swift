import Foundation
import HTTPTypes
import OpenAPIRuntime
import TuistLogging

/// Resumes an artifact download that fails partway through the response body
/// instead of fetching it again from byte zero.
///
/// A retry at the request level replays the whole transfer, so a download that
/// dies at 90% spends 90% of its bytes for nothing and its replacement starts
/// over. On a congested link that inflates offered load at the worst possible
/// moment. This middleware keeps what already arrived and asks the server for
/// the remainder with a `Range` header, so a retry costs the tail rather than
/// the whole artifact.
///
/// Scoped to the artifact download operations by ID: the body is collected into
/// memory here, which is what those callers already do with it, and is not a
/// change worth making for every response the client handles.
public struct ArtifactResumeMiddleware: ClientMiddleware {
    /// Cap on resume attempts for one logical download. Each attempt makes
    /// forward progress, so this bounds a server that keeps truncating rather
    /// than the usual case of a single dropped connection.
    public static let defaultMaximumResumeAttempts = 3

    private let resumableOperationIDs: Set<String>
    private let maximumResumeAttempts: Int

    public init(
        resumableOperationIDs: Set<String>,
        maximumResumeAttempts: Int = ArtifactResumeMiddleware.defaultMaximumResumeAttempts
    ) {
        self.resumableOperationIDs = resumableOperationIDs
        self.maximumResumeAttempts = max(0, maximumResumeAttempts)
    }

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        guard maximumResumeAttempts > 0,
              request.method == .get,
              resumableOperationIDs.contains(operationID)
        else {
            return try await next(request, body, baseURL)
        }

        let (response, responseBody) = try await next(request, body, baseURL)
        // Only a whole-artifact success is resumable. Errors carry a short JSON
        // body the caller needs verbatim, and a server that already answered
        // 206 was not asked to by this middleware.
        guard response.status.code == 200, let responseBody else {
            return (response, responseBody)
        }

        var collected = Data()
        var pending: HTTPBody? = responseBody
        var attempt = 0

        while let stream = pending {
            pending = nil
            do {
                for try await chunk in stream {
                    collected.append(contentsOf: chunk)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard attempt < maximumResumeAttempts, !collected.isEmpty else { throw error }
                attempt += 1
                Logger.current.debug(
                    "Artifact download for \(request.path ?? "") failed after \(collected.count) bytes: \(error.localizedDescription), resuming (\(attempt)/\(maximumResumeAttempts))..."
                )
                guard let resumed = try await resume(
                    from: collected.count,
                    request: request,
                    baseURL: baseURL,
                    next: next
                ) else {
                    throw error
                }
                switch resumed {
                case let .partial(body):
                    pending = body
                case let .whole(body):
                    // The server ignored the range and started over, so the
                    // bytes already held describe nothing. Anything else would
                    // splice the artifact's head onto its own head.
                    collected = Data()
                    pending = body
                }
            }
        }

        return (response, HTTPBody(collected))
    }

    // MARK: - Private

    private enum ResumedBody {
        /// A `206` whose `Content-Range` starts exactly where the transfer
        /// stopped, so its bytes append to what is already held.
        case partial(HTTPBody)
        /// A `200`: the server does not honour ranges on this route.
        case whole(HTTPBody)
    }

    private func resume(
        from offset: Int,
        request: HTTPRequest,
        baseURL: URL,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> ResumedBody? {
        var resumeRequest = request
        resumeRequest.headerFields[.range] = "bytes=\(offset)-"

        let (response, body) = try await next(resumeRequest, nil, baseURL)
        guard let body else { return nil }

        switch response.status.code {
        case 206:
            // The offset is verified rather than trusted. A 206 that starts
            // anywhere else, from a proxy rewriting the range or the artifact
            // having been replaced between the two requests, would corrupt the
            // assembled file silently, so it is refused instead.
            guard Self.partialContentStart(of: response) == offset else {
                Logger.current.debug(
                    "Refusing a resumed artifact response whose content-range does not start at \(offset)."
                )
                return nil
            }
            return .partial(body)
        case 200:
            return .whole(body)
        default:
            return nil
        }
    }

    /// The first byte position from a `Content-Range: bytes <start>-<end>/<total>` header.
    static func partialContentStart(of response: HTTPResponse) -> Int? {
        guard let value = response.headerFields[.contentRange] else { return nil }
        guard let range = value.trimmingCharacters(in: .whitespaces).split(separator: " ").last,
              let start = range.split(separator: "-").first,
              let offset = Int(start)
        else {
            return nil
        }
        return offset
    }
}
