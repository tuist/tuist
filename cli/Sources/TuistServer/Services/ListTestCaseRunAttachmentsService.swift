import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

@Mockable
public protocol ListTestCaseRunAttachmentsServicing: Sendable {
    func listTestCaseRunAttachments(
        fullHandle: String,
        serverURL: URL,
        testCaseRunId: String
    ) async throws -> Operations.listTestCaseRunAttachments.Output.Ok.Body.jsonPayload
}

enum ListTestCaseRunAttachmentsServiceError: LocalizedError {
    case unknownError(Int)
    case forbidden(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "We could not list the test case run attachments due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message):
            return message
        case let .notFound(message):
            return message
        }
    }
}

public struct ListTestCaseRunAttachmentsService: ListTestCaseRunAttachmentsServicing {
    private let fullHandleService: FullHandleServicing

    public init() {
        self.init(
            fullHandleService: FullHandleService()
        )
    }

    init(
        fullHandleService: FullHandleServicing
    ) {
        self.fullHandleService = fullHandleService
    }

    public func listTestCaseRunAttachments(
        fullHandle: String,
        serverURL: URL,
        testCaseRunId: String
    ) async throws -> Operations.listTestCaseRunAttachments.Output.Ok.Body.jsonPayload {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.listTestCaseRunAttachments(
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
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw ListTestCaseRunAttachmentsServiceError.forbidden(error.message)
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw ListTestCaseRunAttachmentsServiceError.notFound(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw ListTestCaseRunAttachmentsServiceError.unknownError(statusCode)
        }
    }
}
