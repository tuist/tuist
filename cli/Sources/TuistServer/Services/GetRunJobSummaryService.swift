import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

@Mockable
public protocol GetRunJobSummaryServicing: Sendable {
    func getRunJobSummary(
        fullHandle: String,
        gitRef: String,
        serverURL: URL
    ) async throws -> String?
}

enum GetRunJobSummaryServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The run job summary could not be fetched due to an unknown Tuist response of \(statusCode)."
        case let .unauthorized(message), let .forbidden(message):
            return message
        }
    }
}

public struct GetRunJobSummaryService: GetRunJobSummaryServicing {
    private let fullHandleService: FullHandleServicing

    public init(fullHandleService: FullHandleServicing = FullHandleService()) {
        self.fullHandleService = fullHandleService
    }

    public func getRunJobSummary(
        fullHandle: String,
        gitRef: String,
        serverURL: URL
    ) async throws -> String? {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.getRunJobSummary(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle
                ),
                query: .init(git_ref: gitRef)
            )
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(json):
                return json.markdown
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw GetRunJobSummaryServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw GetRunJobSummaryServiceError.forbidden(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw GetRunJobSummaryServiceError.unknownError(statusCode)
        }
    }
}
