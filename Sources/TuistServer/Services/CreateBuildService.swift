import Foundation
import Mockable
import OpenAPIURLSession

@Mockable
public protocol CreateBuildServicing {
    func createBuild(
        fullHandle: String,
        serverURL: URL,
        id: String,
        duration: Int,
        isCI: Bool,
        modelIdentifier: String?,
        macOSVersion: String,
        scheme: String?,
        xcodeVersion: String?,
        status: ServerBuildRunStatus
    ) async throws
}

enum CreateBuildServiceError: LocalizedError {
    case unknownError(Int)
    case forbidden(String)
    case notFound(String)
    case unauthorized(String)
    case badRequest(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The build could not be uploaded due to an unknown server response of \(statusCode)."
        case let .forbidden(message), let .notFound(message), let .unauthorized(message), let .badRequest(message):
            return message
        }
    }
}

public enum ServerBuildRunStatus {
    case success, failure
}

public final class CreateBuildService: CreateBuildServicing {
    private let fullHandleService: FullHandleServicing

    public init(
        fullHandleService: FullHandleServicing = FullHandleService()
    ) {
        self.fullHandleService = fullHandleService
    }

    public func createBuild(
        fullHandle: String,
        serverURL: URL,
        id: String,
        duration: Int,
        isCI: Bool,
        modelIdentifier: String?,
        macOSVersion: String,
        scheme: String?,
        xcodeVersion: String?,
        status: ServerBuildRunStatus
    ) async throws {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)
        let status: Operations.createRun.Input.Body.jsonPayload.Case1Payload.statusPayload? = switch status {
        case .success:
            .success
        case .failure:
            .failure
        }

        let response = try await client.createRun(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle
                ),
                body: .json(
                    .case1(
                        .init(
                            duration: duration,
                            id: id,
                            is_ci: isCI,
                            macos_version: macOSVersion,
                            model_identifier: modelIdentifier,
                            scheme: scheme,
                            status: status,
                            xcode_version: xcodeVersion
                        )
                    )
                )
            )
        )
        switch response {
        case .ok:
            break
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw CreateBuildServiceError.forbidden(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw CreateBuildServiceError.unknownError(statusCode)
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw CreateBuildServiceError.unauthorized(error.message)
            }
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw CreateBuildServiceError.notFound(error.message)
            }
        case let .badRequest(badRequestResponse):
            switch badRequestResponse.body {
            case let .json(error):
                throw CreateBuildServiceError.badRequest(error.message)
            }
        }
    }
}
