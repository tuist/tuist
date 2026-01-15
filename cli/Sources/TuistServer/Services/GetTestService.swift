import Foundation
import Mockable
import OpenAPIURLSession
import TuistHTTP

@Mockable
public protocol GetTestServicing {
    func getTest(
        fullHandle: String,
        testId: String,
        serverURL: URL
    ) async throws -> Components.Schemas.TestRunRead
}

enum GetTestServiceError: LocalizedError {
    case notFound(String)
    case forbidden(String)
    case unauthorized(String)
    case unknownError(Int)

    var errorDescription: String? {
        switch self {
        case let .notFound(message):
            return message
        case let .forbidden(message):
            return message
        case let .unauthorized(message):
            return message
        case let .unknownError(statusCode):
            return "The test could not be retrieved due to an unknown Tuist response of \(statusCode)."
        }
    }
}

public final class GetTestService: GetTestServicing {
    private let fullHandleService: FullHandleServicing

    public convenience init() {
        self.init(
            fullHandleService: FullHandleService()
        )
    }

    init(fullHandleService: FullHandleServicing) {
        self.fullHandleService = fullHandleService
    }

    public func getTest(
        fullHandle: String,
        testId: String,
        serverURL: URL
    ) async throws -> Components.Schemas.TestRunRead {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.getTest(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    test_id: testId
                )
            )
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(json):
                return json
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw GetTestServiceError.notFound(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw GetTestServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw GetTestServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw GetTestServiceError.unknownError(statusCode)
        }
    }
}
