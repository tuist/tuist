import Foundation
import Mockable
import OpenAPIURLSession
import TuistHTTP

public typealias ServerTestCaseRun = Operations.getTestCaseRun.Output.Ok.Body.jsonPayload

@Mockable
public protocol GetTestCaseRunServicing: Sendable {
    func getTestCaseRun(
        fullHandle: String,
        testCaseRunId: String,
        serverURL: URL
    ) async throws -> ServerTestCaseRun
}

enum GetTestCaseRunServiceError: LocalizedError {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The test case run could not be fetched due to an unknown Tuist response of \(statusCode)."
        case let .notFound(message):
            return message
        case let .forbidden(message):
            return message
        }
    }
}

public struct GetTestCaseRunService: GetTestCaseRunServicing {
    private let fullHandleService: FullHandleServicing

    public init(fullHandleService: FullHandleServicing = FullHandleService()) {
        self.fullHandleService = fullHandleService
    }

    public func getTestCaseRun(
        fullHandle: String,
        testCaseRunId: String,
        serverURL: URL
    ) async throws -> ServerTestCaseRun {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.getTestCaseRun(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    test_case_run_id: testCaseRunId
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
                throw GetTestCaseRunServiceError.notFound(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw GetTestCaseRunServiceError.forbidden(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw GetTestCaseRunServiceError.unknownError(statusCode)
        }
    }
}
