import Foundation
import OpenAPIRuntime

public enum ServerErrorClassifier {
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
