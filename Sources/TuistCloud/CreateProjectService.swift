import Apollo
import Foundation
import TuistCloudSchema
import TuistSupport

public protocol CreateProjectServicing {
    func createProject(
        name: String,
        organizationName: String?,
        serverURL: URL
    ) async throws -> String
}

enum CreateProjectServiceError: FatalError {
    case graphqlError(String)
    case projectCouldNotBeCreated

    var type: ErrorType {
        switch self {
        case .graphqlError:
            return .abort
        case .projectCouldNotBeCreated:
            return .bug
        }
    }

    var description: String {
        switch self {
        case let .graphqlError(description):
            return description
        case .projectCouldNotBeCreated:
            return "The project could not be created."
        }
    }
}

public final class CreateProjectService: CreateProjectServicing {
    public init() {}

    public func createProject(
        name: String,
        organizationName: String?,
        serverURL: URL
    ) async throws -> String {
        let client = ApolloClient(cloudURL: serverURL)

        let response = await withCheckedContinuation { continuation in
            client.perform(
                mutation: CreateProjectMutation(
                    input: CreateProjectInput(
                        name: name,
                        accountName: organizationName
                            .map { GraphQLNullable(stringLiteral: $0) } ?? GraphQLNullable(nilLiteral: ())
                    )
                )
            ) { response in
                continuation.resume(returning: response)
            }
        }

        guard let data = try response.get().data else { throw CreateProjectServiceError.projectCouldNotBeCreated }

        let errors = data.createProject.errors
        if !errors.isEmpty {
            throw CreateProjectServiceError.graphqlError(
                errors.map(\.message).joined(separator: "\n")
            )
        }

        return data.createProject.project?.slug ?? ""
    }
}
