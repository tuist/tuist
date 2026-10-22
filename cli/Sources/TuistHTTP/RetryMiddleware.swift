import Foundation
import HTTPTypes
import OpenAPIRuntime
import TuistLogging

public struct RetryMiddleware: ClientMiddleware {
    private let retryPolicy: HTTPRetryPolicy
    private let retryableRequestMethods: Set<String>?
    private let retriesTransportErrors: Bool
    private let retriesUnforwardedCacheRequests: Bool
    private let idempotentOperationIDs: Set<String>
    private let operationIDsAnsweringServiceUnavailableAfterWriting: Set<String>

    /// GET and HEAD requests, and the operations in `idempotentOperationIDs`, are replayed after any transport
    /// error and after 408, 429 and 5xx responses. Every other request may already have changed state on the
    /// server when its response is lost, so it is replayed only after a failure that shows the server never
    /// processed it: a connection that could not be established, or a 429 or 503 response.
    ///
    /// - Parameters:
    ///   - retriesTransportErrors: When `true` (the default) a thrown transport error,
    ///     including a timeout, is retried. A caller on a fail-fast path passes `false` so a
    ///     hung backend surfaces through its session timeout immediately rather than being
    ///     replayed. Retryable HTTP responses such as 503 are retried regardless of this flag.
    ///   - retriesUnforwardedCacheRequests: Opts otherwise excluded request methods into
    ///     retries after the activation gateway confirms it never forwarded the request.
    ///     Requires a re-iterable body and does not retry transport or ordinary upload failures.
    ///   - idempotentOperationIDs: Non-GET operations the server treats as idempotent.
    ///   - operationIDsAnsweringServiceUnavailableAfterWriting: Non-idempotent operations that can answer 503
    ///     after committing a write. Their 503 is replayed only when it carries `Retry-After`.
    public init(
        maxRetries: Int? = nil,
        baseDelayMilliseconds: UInt64? = nil,
        retryableRequestMethods: Set<String>? = nil,
        retriesTransportErrors: Bool = true,
        retriesUnforwardedCacheRequests: Bool = false,
        idempotentOperationIDs: Set<String> = [],
        operationIDsAnsweringServiceUnavailableAfterWriting: Set<String> = []
    ) {
        retryPolicy = HTTPRetryPolicy(
            maximumRetryCount: maxRetries,
            baseDelayMilliseconds: baseDelayMilliseconds
        )
        self.retryableRequestMethods = retryableRequestMethods
        self.retriesTransportErrors = retriesTransportErrors
        self.retriesUnforwardedCacheRequests = retriesUnforwardedCacheRequests
        self.idempotentOperationIDs = idempotentOperationIDs
        self.operationIDsAnsweringServiceUnavailableAfterWriting = operationIDsAnsweringServiceUnavailableAfterWriting
    }

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        if let retryableRequestMethods,
           !retryableRequestMethods.contains(request.method.rawValue)
        {
            // The activation gateway guarantees these rejections never reached
            // the artifact backend. Preserve streaming and only replay bodies
            // that the caller explicitly made re-iterable.
            for attempt in 0 ... retryPolicy.maximumRetryCount {
                try Task<Never, Never>.checkCancellation()
                let (response, responseBody) = try await next(request, body, baseURL)
                if let error = Self.authorizationThrottledError(for: response) {
                    throw error
                }
                guard retriesUnforwardedCacheRequests,
                      body == nil || body?.iterationBehavior == .multiple,
                      attempt < retryPolicy.maximumRetryCount,
                      [429, 503].contains(response.status.code),
                      response.headerFields[HTTPField.Name("X-Tuist-Cache-Activation")!] == "pending"
                else {
                    return (response, responseBody)
                }
                try await Task<Never, Never>.sleep(nanoseconds: Self.retryDelay(
                    for: response, policyDelay: retryPolicy.delay(for: attempt)
                ))
            }
        }

        let bodyData: Data?
        if let body {
            bodyData = try await Data(collecting: body, upTo: .max)
        } else {
            bodyData = nil
        }

        let idempotent = [.get, .head].contains(request.method) || idempotentOperationIDs.contains(operationID)
        for retry in 0 ..< retryPolicy.maximumRetryCount {
            let replayBody = bodyData.map { HTTPBody($0) }
            var delay = retryPolicy.delay(for: retry)
            do {
                let (response, responseBody) = try await next(request, replayBody, baseURL)
                if let error = Self.authorizationThrottledError(for: response) {
                    throw error
                }
                guard isRetryable(response, idempotent: idempotent, operationID: operationID) else {
                    return (response, responseBody)
                }
                delay = Self.retryDelay(for: response, policyDelay: delay)
                Logger.current.debug(
                    "Received HTTP \(response.status.code) for \(request.method.rawValue) \(request.path ?? ""), retrying (\(retry + 1)/\(retryPolicy.maximumRetryCount))..."
                )
            } catch let error as AuthorizationThrottledError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try rethrowUnlessReplayable(error, idempotent: idempotent)
                Logger.current.debug(
                    "HTTP request failed for \(request.method.rawValue) \(request.path ?? ""): \(error.localizedDescription), retrying (\(retry + 1)/\(retryPolicy.maximumRetryCount))..."
                )
            }
            try await Task<Never, Never>.sleep(nanoseconds: delay)
        }

        try Task<Never, Never>.checkCancellation()
        let replayBody = bodyData.map { HTTPBody($0) }
        do {
            return try await next(request, replayBody, baseURL)
        } catch {
            throw Self.credentialAcquisitionError(in: error)?.underlyingError ?? error
        }
    }

    private func isRetryable(_ response: HTTPResponse, idempotent: Bool, operationID: String) -> Bool {
        let statusCode = response.status.code
        if idempotent {
            return statusCode == 408 || statusCode == 429 || (500 ..< 600).contains(statusCode)
        }
        if statusCode == 503, operationIDsAnsweringServiceUnavailableAfterWriting.contains(operationID) {
            return response.headerFields[HTTPField.Name("Retry-After")!] != nil
        }
        return statusCode == 429 || statusCode == 503
    }

    private func rethrowUnlessReplayable(_ error: any Error, idempotent: Bool) throws {
        if let credentialError = Self.credentialAcquisitionError(in: error) {
            guard retriesTransportErrors, Self.isConnectionEstablishmentFailure(credentialError.underlyingError)
            else { throw credentialError.underlyingError }
        } else if !retriesTransportErrors || !(idempotent || Self.isConnectionEstablishmentFailure(error)) {
            throw error
        }
    }

    private static func credentialAcquisitionError(in error: any Error) -> CredentialAcquisitionError? {
        if let error = error as? CredentialAcquisitionError { return error }
        return (error as? ClientError)?.underlyingError as? CredentialAcquisitionError
    }

    /// Whether `error` shows the request never reached the server because no connection to it could be set up.
    private static func isConnectionEstablishmentFailure(_ error: any Error) -> Bool {
        switch error {
        case let error as ClientError:
            return isConnectionEstablishmentFailure(error.underlyingError)
        case let error as CredentialAcquisitionError:
            return isConnectionEstablishmentFailure(error.underlyingError)
        case let error as URLError:
            return [
                .cannotConnectToHost,
                .cannotFindHost,
                .dnsLookupFailed,
                .notConnectedToInternet,
                .secureConnectionFailed,
            ].contains(error.code)
        default:
            return false
        }
    }

    private static func authorizationThrottledError(for response: HTTPResponse) -> AuthorizationThrottledError? {
        let throttleReasonName = HTTPField.Name("x-tuist-throttle-reason")!
        guard response.headerFields[throttleReasonName] == "authorization" else { return nil }

        let retryAfterName = HTTPField.Name("Retry-After")!
        let retryAfterSeconds = response.headerFields[retryAfterName]
            .flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        return AuthorizationThrottledError(retryAfterSeconds: retryAfterSeconds)
    }

    static func retryDelay(for response: HTTPResponse, policyDelay: UInt64) -> UInt64 {
        let retryAfterName = HTTPField.Name("Retry-After")!
        guard let value = response.headerFields[retryAfterName],
              let seconds = UInt64(value.trimmingCharacters(in: .whitespaces))
        else {
            return policyDelay
        }
        let milliseconds = seconds.multipliedReportingOverflow(by: 1000)
        let boundedMilliseconds = milliseconds.overflow
            ? HTTPRetryPolicy.maximumDelayMilliseconds
            : min(milliseconds.partialValue, HTTPRetryPolicy.maximumDelayMilliseconds)
        let retryAfter = boundedMilliseconds * 1_000_000
        guard retryAfter > 0 else { return policyDelay }
        return max(policyDelay, retryAfter + jitter(onTopOf: retryAfter))
    }

    /// `Retry-After` is a floor expressed in whole seconds, so without a smear across the
    /// second it names every client the server shed at once wakes on the same instant.
    private static func jitter(onTopOf retryAfter: UInt64) -> UInt64 {
        let maximumDelay = HTTPRetryPolicy.maximumDelayMilliseconds * 1_000_000
        let span = min(retryAfterResolutionNanoseconds, maximumDelay - retryAfter)
        guard span > 0 else { return 0 }
        return UInt64.random(in: 0 ... span)
    }

    private static let retryAfterResolutionNanoseconds: UInt64 = 1_000_000_000
}
