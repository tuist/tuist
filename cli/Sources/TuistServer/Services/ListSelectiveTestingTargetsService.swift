import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

@Mockable
public protocol ListSelectiveTestingTargetsServicing: Sendable {
    func listSelectiveTestingTargets(
        fullHandle: String,
        serverURL: URL,
        testRunId: String,
        hitStatus: String?,
        page: Int?,
        pageSize: Int
    ) async throws -> Operations.listSelectiveTestingTargets.Output.Ok.Body.jsonPayload
}

enum ListSelectiveTestingTargetsServiceError: LocalizedError {
    case unknownError(Int)
    case forbidden(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "We could not list the selective testing targets due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message), let .notFound(message):
            return message
        }
    }
}

public struct ListSelectiveTestingTargetsService: ListSelectiveTestingTargetsServicing {
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

    public func listSelectiveTestingTargets(
        fullHandle: String,
        serverURL: URL,
        testRunId: String,
        hitStatus: String?,
        page: Int?,
        pageSize: Int
    ) async throws -> Operations.listSelectiveTestingTargets.Output.Ok.Body.jsonPayload {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.listSelectiveTestingTargets(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    test_run_id: testRunId
                ),
                query: .init(
                    hit_status: hitStatus.flatMap {
                        Operations.listSelectiveTestingTargets.Input.Query.hit_statusPayload(rawValue: $0)
                    },
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
                throw ListSelectiveTestingTargetsServiceError.forbidden(error.message)
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw ListSelectiveTestingTargetsServiceError.notFound(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw ListSelectiveTestingTargetsServiceError.unknownError(statusCode)
        }
    }
}
