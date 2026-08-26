import Foundation
import OpenAPIRuntime
import TuistHTTP

public enum ServerErrorClassifier {
    /// Whether re-sending the request that raised `error` could produce a different outcome.
    /// Errors that do not carry a status code are retryable, so a failure this classifier does
    /// not model keeps the retries it has today.
    public static func isRetryable(_ error: Error) -> Bool {
        switch error {
        case let error as any HTTPStatusCodeError:
            return !HTTPRetryPolicy.isPermanentClientError(statusCode: error.httpStatusCode)
        case let error as ClientError:
            return isRetryable(error.underlyingError)
        default:
            return true
        }
    }

    public static func isTransient(_ error: Error) -> Bool {
        switch error {
        case let error as RefreshAuthTokenServiceError:
            guard case let .unknownError(statusCode) = error else { return false }
            return isTransient(statusCode: statusCode)
        case let error as GetCacheEndpointsServiceError:
            guard case let .unknownError(statusCode) = error else { return false }
            return isTransient(statusCode: statusCode)
        case let error as ClientError:
            return isTransient(error.underlyingError)
        default:
            return isTransientURLLoadingError(error)
        }
    }

    private static func isTransient(statusCode: Int) -> Bool {
        statusCode == 408 || statusCode == 429 || (500 ... 599).contains(statusCode)
    }

    private static func isTransientURLLoadingError(_ error: Error) -> Bool {
        let error = error as NSError
        guard error.domain == NSURLErrorDomain else { return false }

        return [
            URLError.Code.timedOut,
            .cannotFindHost,
            .cannotConnectToHost,
            .networkConnectionLost,
            .dnsLookupFailed,
            .notConnectedToInternet,
            .resourceUnavailable,
        ].contains(URLError.Code(rawValue: error.code))
    }
}
