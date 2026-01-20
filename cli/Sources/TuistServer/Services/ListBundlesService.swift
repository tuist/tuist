import Foundation
import Mockable
import OpenAPIURLSession
import TuistHTTP

@Mockable
public protocol ListBundlesServicing: Sendable {
    func listBundles(
        fullHandle: String,
        gitBranch: String?,
        page: Int?,
        pageSize: Int?,
        serverURL: URL
    ) async throws -> Operations.listBundles.Output.Ok.Body.jsonPayload
}

enum ListBundlesServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The bundles could not be listed due to an unknown Tuist response of \(statusCode)."
        case let .unauthorized(message):
            return message
        case let .forbidden(message):
            return message
        }
    }
}

public final class ListBundlesService: ListBundlesServicing {
    private let fullHandleService: FullHandleServicing

    public convenience init() {
        self.init(
            fullHandleService: FullHandleService()
        )
    }

    init(
        fullHandleService: FullHandleServicing
    ) {
        self.fullHandleService = fullHandleService
    }

    public func listBundles(
        fullHandle: String,
        gitBranch: String?,
        page: Int?,
        pageSize: Int?,
        serverURL: URL
    ) async throws -> Operations.listBundles.Output.Ok.Body.jsonPayload {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.listBundles(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle
                ),
                query: .init(
                    page: page,
                    page_size: pageSize,
                    git_branch: gitBranch
                )
            )
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(json):
                return json
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw ListBundlesServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw ListBundlesServiceError.forbidden(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw ListBundlesServiceError.unknownError(statusCode)
        }
    }
}
