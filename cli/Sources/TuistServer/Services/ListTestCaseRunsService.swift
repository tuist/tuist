import Foundation
import Mockable
import OpenAPIURLSession
import TuistHTTP

@Mockable
public protocol ListTestCaseRunsServicing {
    func listTestCaseRuns(
        fullHandle: String,
        serverURL: URL,
        moduleName: String,
        name: String,
        suiteName: String?,
        flaky: Bool?,
        page: Int?,
        pageSize: Int
    ) async throws -> Operations.listTestCaseRuns.Output.Ok.Body.jsonPayload
}

enum ListTestCaseRunsServiceError: LocalizedError {
    case unknownError(Int)
    case forbidden(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "We could not list the test case runs due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message):
            return message
        }
    }
}

public struct ListTestCaseRunsService: ListTestCaseRunsServicing {
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

    public func listTestCaseRuns(
        fullHandle: String,
        serverURL: URL,
        moduleName: String,
        name: String,
        suiteName: String?,
        flaky: Bool?,
        page: Int?,
        pageSize: Int
    ) async throws -> Operations.listTestCaseRuns.Output.Ok.Body.jsonPayload {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.listTestCaseRuns(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle
                ),
                query: .init(
                    module_name: moduleName,
                    name: name,
                    suite_name: suiteName,
                    flaky: flaky,
                    page_size: pageSize,
                    page: page
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
                throw ListTestCaseRunsServiceError.forbidden(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw ListTestCaseRunsServiceError.unknownError(statusCode)
        }
    }
}
