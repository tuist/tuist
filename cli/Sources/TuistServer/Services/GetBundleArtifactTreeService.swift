import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

@Mockable
public protocol GetBundleArtifactTreeServicing: Sendable {
    func getBundleArtifactTree(
        fullHandle: String,
        serverURL: URL,
        bundleId: String
    ) async throws -> Operations.getBundleArtifactTree.Output.Ok.Body.jsonPayload
}

enum GetBundleArtifactTreeServiceError: LocalizedError {
    case unknownError(Int)
    case forbidden(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "We could not get the bundle artifact tree due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message), let .notFound(message):
            return message
        }
    }
}

public struct GetBundleArtifactTreeService: GetBundleArtifactTreeServicing {
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

    public func getBundleArtifactTree(
        fullHandle: String,
        serverURL: URL,
        bundleId: String
    ) async throws -> Operations.getBundleArtifactTree.Output.Ok.Body.jsonPayload {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.getBundleArtifactTree(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    bundle_id: bundleId
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
                throw GetBundleArtifactTreeServiceError.forbidden(error.message)
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw GetBundleArtifactTreeServiceError.notFound(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw GetBundleArtifactTreeServiceError.unknownError(statusCode)
        }
    }
}
