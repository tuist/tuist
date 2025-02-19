import Foundation
import Mockable
import OpenAPIURLSession
import TuistSupport

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
        xcodeVersion: String?
    ) async throws
}

enum CreateBuildServiceError: FatalError {
    case unknownError(Int)
    case forbidden(String)
    case badRequest(String)
    case unauthorized(String)

    var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .forbidden, .badRequest, .unauthorized:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "The project could not be created due to an unknown Cloud response of \(statusCode)."
        case let .forbidden(message), let .badRequest(message), let .unauthorized(message):
            return message
        }
    }
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
        xcodeVersion: String?
    ) async throws {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)
        
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
                            xcode_version: xcodeVersion
                        )
                    )
                )
            )
        )
        switch response {
        case .ok:
            break
        case .forbidden:
            break
        case .notFound:
            break
        case .unauthorized:
            break
//        case let .ok(okResponse):
//            switch okResponse.body {
//            case let .json(project):
//                return ServerProject(project)
//            }
//        case let .forbidden(forbiddenResponse):
//            switch forbiddenResponse.body {
//            case let .json(error):
//                throw CreateBuildServiceError.forbidden(error.message)
//            }
//        case let .undocumented(statusCode: statusCode, _):
//            throw CreateBuildServiceError.unknownError(statusCode)
//        case let .badRequest(badRequestResponse):
//            switch badRequestResponse.body {
//            case let .json(error):
//                throw CreateBuildServiceError.badRequest(error.message)
//            }
//        case let .unauthorized(unauthorized):
//            switch unauthorized.body {
//            case let .json(error):
//                throw DeleteOrganizationServiceError.unauthorized(error.message)
//            }
        case .undocumented(statusCode: let statusCode, _):
            break
        }
    }
}
