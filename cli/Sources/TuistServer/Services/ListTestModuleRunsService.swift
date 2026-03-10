import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

@Mockable
public protocol ListTestModuleRunsServicing: Sendable {
    func listTestModuleRuns(
        fullHandle: String,
        serverURL: URL,
        testRunId: String,
        status: String?,
        page: Int?,
        pageSize: Int
    ) async throws -> Operations.listTestModuleRuns.Output.Ok.Body.jsonPayload
}

enum ListTestModuleRunsServiceError: LocalizedError {
    case unknownError(Int)
    case forbidden(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "We could not list the test module runs due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message):
            return message
        case let .notFound(message):
            return message
        }
    }
}

public struct ListTestModuleRunsService: ListTestModuleRunsServicing {
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

    public func listTestModuleRuns(
        fullHandle: String,
        serverURL: URL,
        testRunId: String,
        status: String?,
        page: Int?,
        pageSize: Int
    ) async throws -> Operations.listTestModuleRuns.Output.Ok.Body.jsonPayload {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.listTestModuleRuns(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    test_run_id: testRunId
                ),
                query: .init(
                    status: status.flatMap { Operations.listTestModuleRuns.Input.Query.statusPayload(rawValue: $0) },
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
                throw ListTestModuleRunsServiceError.forbidden(error.message)
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw ListTestModuleRunsServiceError.notFound(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw ListTestModuleRunsServiceError.unknownError(statusCode)
        }
    }
}
