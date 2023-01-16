import Apollo
import Foundation
import TuistCloudSchema
import TuistSupport

public protocol CreateProjectServicing {
    func createProject(
        name: String,
        organizationName: String?,
        serverURL: URL
    ) async throws
}

enum CreateProjectServiceError: FatalError {
    case graphqlError(String)

    var type: ErrorType {
        switch self {
        case .graphqlError:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .graphqlError(description):
            return description
        }
    }
}

public final class CreateProjectService: CreateProjectServicing {
    public init() {}

    public func createProject(
        name: String,
        organizationName: String?,
        serverURL: URL
    ) async throws {
        let client = ApolloClient(cloudURL: serverURL)

        let response = await withCheckedContinuation { continuation in
            client.perform(
                mutation: CreateProjectMutation(
                    input: CreateProjectInput(
                        name: name,
                        accountName: organizationName.map { GraphQLNullable(stringLiteral: $0) } ?? GraphQLNullable(nilLiteral: ())
                    )
                )
            ) { response in
                continuation.resume(returning: response)
            }
        }

        if let errors = try response.get().data?.createProject.errors, !errors.isEmpty {
            throw CreateProjectServiceError.graphqlError(
                errors.map(\.message).joined(separator: "\n")
            )
        }
    }
}
