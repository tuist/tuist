import Foundation
import Mockable
import OpenAPIURLSession
import TuistHTTP

public typealias Generation = Operations.getGeneration.Output.Ok.Body.jsonPayload

@Mockable
public protocol GetGenerationServicing: Sendable {
    func getGeneration(
        fullHandle: String,
        generationId: String,
        serverURL: URL
    ) async throws -> Generation
}

enum GetGenerationServiceError: LocalizedError {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The generation could not be fetched due to an unknown Tuist response of \(statusCode)."
        case let .notFound(message):
            return message
        case let .forbidden(message):
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
        generationId: String,
        serverURL: URL
    ) async throws -> Generation {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.getGeneration(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    generation_id: generationId
                )
            )
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(json):
                return json
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
        case let .undocumented(statusCode: statusCode, _):
            throw GetGenerationServiceError.unknownError(statusCode)
        }
    }
}
