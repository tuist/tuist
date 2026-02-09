import Foundation
import Mockable
import OpenAPIURLSession
import TuistHTTP

public typealias ServerTestCase = Operations.getTestCase.Output.Ok.Body.jsonPayload

@Mockable
public protocol GetTestCaseServicing: Sendable {
    func getTestCase(
        fullHandle: String,
        testCaseId: String,
        serverURL: URL
    ) async throws -> ServerTestCase
}

enum GetTestCaseServiceError: LocalizedError {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The test case could not be fetched due to an unknown Tuist response of \(statusCode)."
        case let .notFound(message):
            return message
        case let .forbidden(message):
            return message
        }
    }
}

public struct GetTestCaseService: GetTestCaseServicing {
    private let fullHandleService: FullHandleServicing

    public init(fullHandleService: FullHandleServicing = FullHandleService()) {
        self.fullHandleService = fullHandleService
    }

    public func getTestCase(
        fullHandle: String,
        testCaseId: String,
        serverURL: URL
    ) async throws -> ServerTestCase {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.getTestCase(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    test_case_id: testCaseId
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
                throw GetTestCaseServiceError.notFound(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw GetTestCaseServiceError.forbidden(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw GetTestCaseServiceError.unknownError(statusCode)
        }
    }
}
