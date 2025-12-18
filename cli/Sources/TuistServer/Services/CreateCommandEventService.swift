#if canImport(TuistCore)
    import Foundation
    import Mockable
    import OpenAPIURLSession
    import TuistCore
    import XcodeGraph

    @Mockable
    public protocol CreateCommandEventServicing {
        func createCommandEvent(
            commandEvent: CommandEvent,
            projectId: String,
            serverURL: URL
        ) async throws -> ServerCommandEvent
    }

    enum CreateCommandEventServiceError: LocalizedError {
        case unknownError(Int)
        case forbidden(String)
        case unauthorized(String)

        var errorDescription: String? {
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
                            build_run_id: commandEvent.buildRunId,
                            cache_endpoint: commandEvent.cacheEndpoint.isEmpty ? nil : commandEvent.cacheEndpoint,
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
                            ran_at: commandEvent.ranAt.ISO8601Format(),
                            status: status,
                            subcommand: commandEvent.subcommand,
                            swift_version: commandEvent.swiftVersion,
                            test_run_id: commandEvent.testRunId,
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
                    throw CreateCommandEventServiceError.unauthorized(error.message)
                }
            }
        }

        private func map(graph: RunGraph) -> Operations.createCommandEvent.Input.Body.jsonPayload.xcode_graphPayload {
            .init(
                binary_build_duration: graph.binaryBuildDuration.map { Int($0) },
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
                                            build_duration: binaryCacheMetadata.buildDuration.map { Int($0) },
                                            hash: binaryCacheMetadata.hash,
                                            hit: hit,
                                            subhashes: binaryCacheMetadata.subhashes.map { subhashes in
                                                .init(
                                                    additional_strings: subhashes.additionalStrings,
                                                    buildable_folders: subhashes.buildableFolders,
                                                    copy_files: subhashes.copyFiles,
                                                    core_data_models: subhashes.coreDataModels,
                                                    dependencies: subhashes.dependencies,
                                                    deployment_target: subhashes.deploymentTarget,
                                                    entitlements: subhashes.entitlements,
                                                    environment: subhashes.environment,
                                                    external: subhashes.external,
                                                    headers: subhashes.headers,
                                                    info_plist: subhashes.infoPlist,
                                                    project_settings: subhashes.projectSettings,
                                                    resources: subhashes.resources,
                                                    sources: subhashes.sources,
                                                    target_scripts: subhashes.targetScripts,
                                                    target_settings: subhashes.targetSettings
                                                )
                                            }
                                        )
                                    },
                                bundle_id: target.bundleId,
                                destinations: target.destinations.map { map(destination: $0) },
                                name: target.name,
                                product: map(product: target.product),
                                product_name: target.productName,
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

        private func map(
            product: XcodeGraph.Product
        ) -> Operations.createCommandEvent.Input.Body.jsonPayload.xcode_graphPayload.projectsPayloadPayload
            .targetsPayloadPayload.productPayload
        {
            switch product {
            case .app: .app
            case .staticLibrary: .static_library
            case .dynamicLibrary: .dynamic_library
            case .framework: .framework
            case .staticFramework: .static_framework
            case .unitTests: .unit_tests
            case .uiTests: .ui_tests
            case .bundle: .bundle
            case .commandLineTool: .command_line_tool
            case .appExtension: .app_extension
            case .watch2App: .watch_2_app
            case .watch2Extension: .watch_2_extension
            case .tvTopShelfExtension: .tv_top_shelf_extension
            case .messagesExtension: .messages_extension
            case .stickerPackExtension: .sticker_pack_extension
            case .appClip: .app_clip
            case .xpc: .xpc
            case .systemExtension: .system_extension
            case .extensionKitExtension: .extension_kit_extension
            case .macro: .macro
            }
        }

        private func map(
            destination: XcodeGraph.Destination
        ) -> Operations.createCommandEvent.Input.Body.jsonPayload.xcode_graphPayload.projectsPayloadPayload
            .targetsPayloadPayload.destinationsPayloadPayload
        {
            switch destination {
            case .iPhone: .iphone
            case .iPad: .ipad
            case .mac: .mac
            case .macWithiPadDesign: .mac_with_ipad_design
            case .macCatalyst: .mac_catalyst
            case .appleWatch: .apple_watch
            case .appleTv: .apple_tv
            case .appleVision: .apple_vision
            case .appleVisionWithiPadDesign: .apple_vision_with_ipad_design
            }
        }
    }
#endif
