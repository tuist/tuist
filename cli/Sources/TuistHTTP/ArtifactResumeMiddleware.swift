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
/// Scoped to the artifact download operations by ID, and within those to a
/// response body that is actually streamed: a transport that hands over an
/// already-materialised body has nothing to resume, and buffering it here would
/// duplicate an artifact that is whole in memory already.
///
/// Resume also requires a validator. The offset a resumed response starts at
/// cannot on its own establish that its bytes belong to the same artifact as
/// the ones already held, so a server that does not identify the
/// representation it is serving does not get resumed.
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
        // A body the transport already holds in full cannot fail partway
        // through, and re-reading it costs nothing, so there is nothing here to
        // buy: collecting it would only add a second full copy of the artifact
        // alongside the transport's, and a third once it is handed back.
        guard responseBody.iterationBehavior == .single else {
            return (response, responseBody)
        }
        // The representation the bytes below belong to. Without it a resumed
        // response cannot be told apart from a different artifact's tail, so
        // there is no safe way to append and the transfer is left to fail.
        guard let validator = response.headerFields[.eTag] else {
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
                    validator: validator,
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
        validator: String,
        request: HTTPRequest,
        baseURL: URL,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> ResumedBody? {
        var resumeRequest = request
        resumeRequest.headerFields[.range] = "bytes=\(offset)-"
        // Asks the server to answer with the tail only while it still holds the
        // representation the earlier bytes came from, and with the whole
        // artifact otherwise.
        resumeRequest.headerFields[.ifRange] = validator

        let (response, body) = try await next(resumeRequest, nil, baseURL)
        guard let body else { return nil }

        switch response.status.code {
        case 206:
            // Both halves are verified rather than trusted. The offset catches a
            // proxy that rewrote the range; the validator catches the artifact
            // having been replaced, which the offset cannot see because a
            // replacement's tail starts exactly where the client asked and may
            // even be the same length. A server that honours `If-Range` will
            // have answered 200 already, so this is the guard for one that does
            // not: appending either way would splice two artifacts together and
            // store the result under a key that describes neither.
            guard Self.partialContentStart(of: response) == offset else {
                Logger.current.debug(
                    "Refusing a resumed artifact response whose content-range does not start at \(offset)."
                )
                return nil
            }
            guard response.headerFields[.eTag].map({ $0 == validator }) ?? true else {
                Logger.current.debug(
                    "Refusing a resumed artifact response that identifies a different representation."
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
