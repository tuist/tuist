import Foundation
import Mockable
import OpenAPIURLSession
import TuistHTTP

@Mockable
public protocol GetGenerationServicing {
    func getGeneration(
        fullHandle: String,
        runId: String,
        serverURL: URL
    ) async throws -> Components.Schemas.Run
}

enum GetGenerationServiceError: LocalizedError {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)
    case unauthorized(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "We could not get the generation due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message), let .notFound(message), let .unauthorized(message):
            return message
        }
    }
}

public final class GetGenerationService: GetGenerationServicing {
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

    public func getGeneration(
        fullHandle: String,
        runId: String,
        serverURL: URL
    ) async throws -> Components.Schemas.Run {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.getGeneration(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    run_id: runId
                )
            )
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(run):
                return run
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw GetGenerationServiceError.notFound(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw GetGenerationServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw GetGenerationServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw GetGenerationServiceError.unknownError(statusCode)
        }
    }
}
