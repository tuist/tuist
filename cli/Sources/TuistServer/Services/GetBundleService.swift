import Foundation
import Mockable
import OpenAPIURLSession

@Mockable
public protocol GetBundleServicing {
    func getBundle(
        serverURL: URL,
        fullHandle: String?,
        bundleId: String
    ) async throws -> ServerBundle
}

enum GetBundleServiceError: LocalizedError {
    case unknownError(Int)
    case forbidden(String)
    case unauthorized(String)
    case notFound(String)
    case projectNotFound(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The bundle could not be retrieved due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message), let .unauthorized(message), let .notFound(message), let .projectNotFound(message):
            return message
        }
    }
}

public final class GetBundleService: GetBundleServicing {
    public init() {}

    public func getBundle(
        serverURL: URL,
        fullHandle: String?,
        bundleId: String
    ) async throws -> ServerBundle {
        guard let fullHandle,
              let components = fullHandle.split(separator: "/", maxSplits: 1),
              components.count == 2
        else {
            throw GetBundleServiceError.projectNotFound("Project not found. Make sure you are in a project directory with a valid configuration.")
        }

        let accountHandle = String(components[0])
        let projectHandle = String(components[1])

        let client = Client.authenticated(serverURL: serverURL)

        let response = try await client.getBundle(
            path: .init(
                account_handle: accountHandle,
                project_handle: projectHandle,
                bundle_id: bundleId
            )
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(bundleData):
                // Temporary implementation until OpenAPI spec is properly updated
                return ServerBundle.test()
            }
        case let .not_found(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw GetBundleServiceError.notFound(error.message)
            }
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw GetBundleServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorizedResponse):
            switch unauthorizedResponse.body {
            case let .json(error):
                throw GetBundleServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw GetBundleServiceError.unknownError(statusCode)
        }
    }

    private func parseArtifacts(_ artifacts: [Components.Schemas.BundleArtifact]?) -> [ServerBundleArtifact]? {
        guard let artifacts else { return nil }
        return artifacts.map { artifact in
            ServerBundleArtifact(
                id: artifact.id,
                artifactType: artifact.artifact_type,
                path: artifact.path,
                size: artifact.size,
                shasum: artifact.shasum,
                children: parseArtifacts(artifact.children)
            )
        }
    }

    private func parseDate(from dateString: String?) -> Date? {
        guard let dateString else { return nil }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: dateString)
    }
}