import Foundation
import Mockable
import OpenAPIURLSession

@Mockable
public protocol ListBundlesServicing {
    func listBundles(
        serverURL: URL,
        fullHandle: String?,
        gitBranch: String?,
        page: Int?,
        pageSize: Int?
    ) async throws -> ServerBundleListResponse
}

enum ListBundlesServiceError: LocalizedError {
    case unknownError(Int)
    case forbidden(String)
    case unauthorized(String)
    case projectNotFound(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The bundles could not be listed due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message), let .unauthorized(message), let .projectNotFound(message):
            return message
        }
    }
}

public final class ListBundlesService: ListBundlesServicing {
    public init() {}

    public func listBundles(
        serverURL: URL,
        fullHandle: String?,
        gitBranch: String?,
        page: Int?,
        pageSize: Int?
    ) async throws -> ServerBundleListResponse {
        guard let fullHandle,
              let components = fullHandle.split(separator: "/", maxSplits: 1),
              components.count == 2
        else {
            throw ListBundlesServiceError.projectNotFound("Project not found. Make sure you are in a project directory with a valid configuration.")
        }

        let accountHandle = String(components[0])
        let projectHandle = String(components[1])

        let client = Client.authenticated(serverURL: serverURL)

        var queryItems: [URLQueryItem] = []
        if let gitBranch {
            queryItems.append(URLQueryItem(name: "git_branch", value: gitBranch))
        }
        if let page {
            queryItems.append(URLQueryItem(name: "page", value: String(page)))
        }
        if let pageSize {
            queryItems.append(URLQueryItem(name: "page_size", value: String(pageSize)))
        }

        let response = try await client.listBundles(
            path: .init(account_handle: accountHandle, project_handle: projectHandle),
            query: .init(
                git_branch: gitBranch,
                page: page.map(Int32.init),
                page_size: pageSize.map(Int32.init)
            )
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(data):
                // Temporary implementation until OpenAPI spec is properly updated
                // We'll need to manually parse the JSON for now
                let bundles: [ServerBundle] = []
                let meta: ServerBundleListMeta? = nil
                return ServerBundleListResponse(bundles: bundles, meta: meta)
            }
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw ListBundlesServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorizedResponse):
            switch unauthorizedResponse.body {
            case let .json(error):
                throw ListBundlesServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw ListBundlesServiceError.unknownError(statusCode)
        }
    }

    private func parseListBundlesResponse(_ data: any) throws -> ServerBundleListResponse {
        // Note: This implementation will need to be updated once the OpenAPI spec
        // properly defines the bundle list response schema. For now, we'll handle
        // the expected JSON structure.
        
        // Placeholder implementation - this will be properly typed once OpenAPI spec is updated
        let bundles: [ServerBundle] = []
        let meta: ServerBundleListMeta? = nil

        return ServerBundleListResponse(bundles: bundles, meta: meta)
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