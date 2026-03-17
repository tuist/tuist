import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

@Mockable
public protocol ListBuildFilesServicing: Sendable {
    func listBuildFiles(
        fullHandle: String,
        serverURL: URL,
        buildId: String,
        target: String?,
        type: String?,
        sortBy: String?,
        page: Int?,
        pageSize: Int
    ) async throws -> Operations.listBuildFiles.Output.Ok.Body.jsonPayload
}

enum ListBuildFilesServiceError: LocalizedError {
    case unknownError(Int)
    case forbidden(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "We could not list the build files due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message):
            return message
        case let .notFound(message):
            return message
        }
    }
}

public struct ListBuildFilesService: ListBuildFilesServicing {
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

    public func listBuildFiles(
        fullHandle: String,
        serverURL: URL,
        buildId: String,
        target: String?,
        type: String?,
        sortBy: String?,
        page: Int?,
        pageSize: Int
    ) async throws -> Operations.listBuildFiles.Output.Ok.Body.jsonPayload {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.listBuildFiles(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    build_id: buildId
                ),
                query: .init(
                    target: target,
                    _type: type.flatMap { Operations.listBuildFiles.Input.Query._typePayload(rawValue: $0) },
                    sort_by: sortBy.flatMap { Operations.listBuildFiles.Input.Query.sort_byPayload(rawValue: $0) },
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
                throw ListBuildFilesServiceError.forbidden(error.message)
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw ListBuildFilesServiceError.notFound(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw ListBuildFilesServiceError.unknownError(statusCode)
        }
    }
}
