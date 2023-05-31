import Apollo
import Foundation
import TuistCloudSchema
import TuistSupport

public protocol CleanRemoteCacheStorageServicing {
    func cleanRemoteCacheStorage(
        serverURL: URL,
        projectSlug: String
    ) async throws
}

enum CleanRemoteCacheStorageServiceError: FatalError {
    case graphqlError(String)
    case remoteCacheStorageCleanFailed

    var type: ErrorType {
        switch self {
        case .graphqlError:
            return .abort
        case .remoteCacheStorageCleanFailed:
            return .bug
        }
    }

    var description: String {
        switch self {
        case let .graphqlError(description):
            return description
        case .remoteCacheStorageCleanFailed:
            return "Remote cache could not have been cleaned."
        }
    }
}

public final class CleanRemoteCacheStorageService: CleanRemoteCacheStorageServicing {
    public init() {}

    public func cleanRemoteCacheStorage(serverURL: URL, projectSlug: String) async throws {
        let client = ApolloClient(cloudURL: serverURL)

        let response = await withCheckedContinuation { continuation in
            client.perform(
                mutation: ClearRemoteCacheStorageMutation(
                    input: ClearRemoteCacheStorageInput(
                        projectSlug: GraphQLNullable(stringLiteral: projectSlug)
                    )
                )
            ) { response in
                continuation.resume(returning: response)
            }
        }

        guard let data = try response.get().data else { throw CleanRemoteCacheStorageServiceError.remoteCacheStorageCleanFailed }

        let errors = data.clearRemoteCacheStorage.errors
        if !errors.isEmpty {
            throw CleanRemoteCacheStorageServiceError.graphqlError(
                errors.map(\.message).joined(separator: "\n")
            )
        }
    }
}
