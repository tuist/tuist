import Foundation
import Testing

@testable import TuistServer

struct ServerErrorClassifierTests {
    @Test(
        arguments: [408, 429, 500, 502, 503, 599]
    )
    func transientStatusCodesAreTransient(statusCode: Int) {
        #expect(
            ServerErrorClassifier.isTransient(
                RefreshAuthTokenServiceError.unknownError(statusCode)
            )
        )
        #expect(
            ServerErrorClassifier.isTransient(
                GetCacheEndpointsServiceError.unknownError(statusCode)
            )
        )
    }

    @Test(
        arguments: [400, 401, 403, 404]
    )
    func permanentStatusCodesAreNotTransient(statusCode: Int) {
        #expect(
            !ServerErrorClassifier.isTransient(
                RefreshAuthTokenServiceError.unknownError(statusCode)
            )
        )
        #expect(
            !ServerErrorClassifier.isTransient(
                GetCacheEndpointsServiceError.unknownError(statusCode)
            )
        )
    }

    @Test func authenticationAndPermissionErrorsAreNotTransient() {
        #expect(
            !ServerErrorClassifier.isTransient(
                RefreshAuthTokenServiceError.unauthorized("Invalid token")
            )
        )
        #expect(
            !ServerErrorClassifier.isTransient(
                RefreshAuthTokenServiceError.badRequest
            )
        )
        #expect(
            !ServerErrorClassifier.isTransient(
                GetCacheEndpointsServiceError.forbidden("Forbidden")
            )
        )
    }

    @Test(
        arguments: [
            URLError.Code.timedOut,
            .cannotFindHost,
            .cannotConnectToHost,
            .networkConnectionLost,
            .dnsLookupFailed,
            .notConnectedToInternet,
            .resourceUnavailable,
        ]
    )
    func transientURLLoadingErrorsAreTransient(code: URLError.Code) {
        #expect(ServerErrorClassifier.isTransient(URLError(code)))
    }

    @Test func unrelatedErrorsAreNotTransient() {
        #expect(!ServerErrorClassifier.isTransient(NSError(domain: "Test", code: 1)))
    }
}
