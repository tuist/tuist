import Foundation
import Mockable
import OpenAPIURLSession
import TuistCore
import TuistSupport

@Mockable
public protocol CreateCommandEventServicing {
    func createCommandEvent(
        commandEvent: CommandEvent,
        projectId: String,
        serverURL: URL
    ) async throws -> ServerCommandEvent
}

enum CreateCommandEventServiceError: FatalError {
    case unknownError(Int)
    case forbidden(String)
    case unauthorized(String)

    var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .forbidden, .unauthorized:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "The organization could not be created due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message), let .unauthorized(message):
            return message
        }
    }
}

public final class CreateCommandEventService: CreateCommandEventServicing {
    public init() {}

    public func createCommandEvent(
        commandEvent: CommandEvent,
        projectId: String,
        serverURL: URL
    ) async throws -> ServerCommandEvent {
        let client = Client.authenticated(serverURL: serverURL)
        let errorMessage: String?
        let status: Operations.createCommandEvent.Input.Body.jsonPayload.statusPayload?
        switch commandEvent.status {
        case .success:
            errorMessage = nil
            status = .success
        case let .failure(message):
            errorMessage = message
            status = .failure
        }

        let response = try await client.createCommandEvent(
            .init(
                query: .init(
                    project_id: projectId
                ),
                body: .json(
                    .init(
                        client_id: commandEvent.clientId,
                        command_arguments: commandEvent.commandArguments,
                        duration: commandEvent.durationInMs,
                        error_message: errorMessage,
                        git_branch: commandEvent.gitBranch,
                        git_commit_sha: commandEvent.gitCommitSHA,
                        git_ref: commandEvent.gitRef,
                        git_remote_url_origin: commandEvent.gitRemoteURLOrigin,
                        is_ci: commandEvent.isCI,
                        macos_version: commandEvent.macOSVersion,
                        name: commandEvent.name,
                        preview_id: commandEvent.previewId,
                        status: status,
                        subcommand: commandEvent.subcommand,
                        swift_version: commandEvent.swiftVersion,
                        tuist_version: commandEvent.tuistVersion,
                        xcode_graph: commandEvent.graph.map { map(graph: $0) }
                    )
                )
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(commandEvent):
                return ServerCommandEvent(commandEvent)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw CreateCommandEventServiceError.unknownError(statusCode)
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw CreateCommandEventServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw DeleteOrganizationServiceError.unauthorized(error.message)
            }
        }
    }

    private func map(graph: RunGraph) -> Operations.createCommandEvent.Input.Body.jsonPayload.xcode_graphPayload {
        .init(
            name: graph.name,
            projects: graph.projects.map { project in
                .init(
                    name: project.name,
                    path: project.path.pathString,
                    targets: project.targets.map { target in
                        .init(
                            binary_cache_metadata: target.binaryCacheMetadata
                                .map { binaryCacheMetadata in
                                    let hit: Operations.createCommandEvent.Input.Body.jsonPayload
                                        .xcode_graphPayload.projectsPayloadPayload.targetsPayloadPayload
                                        .binary_cache_metadataPayload
                                        .hitPayload = switch binaryCacheMetadata.hit
                                    {
                                    case .local:
                                        .local
                                    case .remote:
                                        .remote
                                    case .miss:
                                        .miss
                                    }
                                    return .init(
                                        hash: binaryCacheMetadata.hash,
                                        hit: hit
                                    )
                                },
                            name: target.name,
                            selective_testing_metadata: target.selectiveTestingMetadata
                                .map { selectiveTestingMetadata in
                                    let hit: Operations.createCommandEvent.Input.Body.jsonPayload
                                        .xcode_graphPayload.projectsPayloadPayload.targetsPayloadPayload
                                        .selective_testing_metadataPayload
                                        .hitPayload = switch selectiveTestingMetadata.hit
                                    {
                                    case .local:
                                        .local
                                    case .remote:
                                        .remote
                                    case .miss:
                                        .miss
                                    }
                                    return .init(
                                        hash: selectiveTestingMetadata.hash,
                                        hit: hit
                                    )
                                }
                        )
                    }
                )
            }
        )
    }
}
