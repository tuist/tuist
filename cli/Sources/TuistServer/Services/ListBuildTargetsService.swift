import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

@Mockable
public protocol ListBuildTargetsServicing: Sendable {
    func listBuildTargets(
        fullHandle: String,
        serverURL: URL,
        buildId: String,
        status: String?,
        page: Int?,
        pageSize: Int
    ) async throws -> Operations.listBuildTargets.Output.Ok.Body.jsonPayload
}

enum ListBuildTargetsServiceError: LocalizedError {
    case unknownError(Int)
    case forbidden(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "We could not list the build targets due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message):
            return message
        case let .notFound(message):
            return message
        }
    }
}

public struct ListBuildTargetsService: ListBuildTargetsServicing {
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

    public func listBuildTargets(
        fullHandle: String,
        serverURL: URL,
        buildId: String,
        status: String?,
        page: Int?,
        pageSize: Int
    ) async throws -> Operations.listBuildTargets.Output.Ok.Body.jsonPayload {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.listBuildTargets(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    build_id: buildId
                ),
                query: .init(
                    status: status.flatMap { Operations.listBuildTargets.Input.Query.statusPayload(rawValue: $0) },
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
                throw ListBuildTargetsServiceError.forbidden(error.message)
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw ListBuildTargetsServiceError.notFound(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw ListBuildTargetsServiceError.unknownError(statusCode)
        }
    }
}
