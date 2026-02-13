import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

public typealias Build = Operations.getBuild.Output.Ok.Body.jsonPayload

@Mockable
public protocol GetBuildServicing {
    func getBuild(
        fullHandle: String,
        buildId: String,
        serverURL: URL
    ) async throws -> Build
}

enum GetBuildServiceError: LocalizedError {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "We could not get the build due to an unknown Tuist response of \(statusCode)."
        case let .notFound(message), let .forbidden(message):
            return message
        }
    }
}

public struct GetBuildService: GetBuildServicing {
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

    public func getBuild(
        fullHandle: String,
        buildId: String,
        serverURL: URL
    ) async throws -> Build {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.getBuild(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    build_id: buildId
                )
            )
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(build):
                return build
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw GetBuildServiceError.notFound(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw GetBuildServiceError.forbidden(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw GetBuildServiceError.unknownError(statusCode)
        }
    }
}
