import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

@Mockable
public protocol ListBuildCASOutputsServicing: Sendable {
    func listBuildCASOutputs(
        fullHandle: String,
        serverURL: URL,
        buildId: String,
        operation: String?,
        type: String?,
        page: Int?,
        pageSize: Int
    ) async throws -> Operations.listBuildCASOutputs.Output.Ok.Body.jsonPayload
}

enum ListBuildCASOutputsServiceError: LocalizedError {
    case unknownError(Int)
    case forbidden(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "We could not list the build CAS outputs due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message), let .notFound(message):
            return message
        }
    }
}

public struct ListBuildCASOutputsService: ListBuildCASOutputsServicing {
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

    public func listBuildCASOutputs(
        fullHandle: String,
        serverURL: URL,
        buildId: String,
        operation: String?,
        type: String?,
        page: Int?,
        pageSize: Int
    ) async throws -> Operations.listBuildCASOutputs.Output.Ok.Body.jsonPayload {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.listBuildCASOutputs(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    build_id: buildId
                ),
                query: .init(
                    operation: operation.flatMap {
                        Operations.listBuildCASOutputs.Input.Query.operationPayload(rawValue: $0)
                    },
                    _type: type.flatMap { Operations.listBuildCASOutputs.Input.Query._typePayload(rawValue: $0) },
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
                throw ListBuildCASOutputsServiceError.forbidden(error.message)
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw ListBuildCASOutputsServiceError.notFound(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw ListBuildCASOutputsServiceError.unknownError(statusCode)
        }
    }
}
