import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

@Mockable
public protocol ListTestSuiteRunsServicing: Sendable {
    func listTestSuiteRuns(
        fullHandle: String,
        serverURL: URL,
        testRunId: String,
        moduleName: String?,
        status: String?,
        page: Int?,
        pageSize: Int
    ) async throws -> Operations.listTestSuiteRuns.Output.Ok.Body.jsonPayload
}

enum ListTestSuiteRunsServiceError: LocalizedError {
    case unknownError(Int)
    case forbidden(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "We could not list the test suite runs due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message):
            return message
        case let .notFound(message):
            return message
        }
    }
}

public struct ListTestSuiteRunsService: ListTestSuiteRunsServicing {
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

    public func listTestSuiteRuns(
        fullHandle: String,
        serverURL: URL,
        testRunId: String,
        moduleName: String?,
        status: String?,
        page: Int?,
        pageSize: Int
    ) async throws -> Operations.listTestSuiteRuns.Output.Ok.Body.jsonPayload {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.listTestSuiteRuns(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    test_run_id: testRunId
                ),
                query: .init(
                    module_name: moduleName,
                    status: status.flatMap { Operations.listTestSuiteRuns.Input.Query.statusPayload(rawValue: $0) },
                    page: page,
                    page_size: pageSize
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
                throw ListTestSuiteRunsServiceError.forbidden(error.message)
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw ListTestSuiteRunsServiceError.notFound(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw ListTestSuiteRunsServiceError.unknownError(statusCode)
        }
    }
}
