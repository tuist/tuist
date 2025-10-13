import Foundation
import Mockable
import OpenAPIURLSession

#if canImport(TuistSupport)
    import TuistCI
    import TuistSupport
    import TuistXCActivityLog

    @Mockable
    public protocol CreateBuildServicing {
        func createBuild(
            fullHandle: String,
            serverURL: URL,
            id: String,
            category: XCActivityBuildCategory,
            configuration: String?,
            duration: Int,
            files: [XCActivityBuildFile],
            gitBranch: String?,
            gitCommitSHA: String?,
            gitRef: String?,
            gitRemoteURLOrigin: String?,
            isCI: Bool,
            issues: [XCActivityIssue],
            modelIdentifier: String?,
            macOSVersion: String,
            scheme: String?,
            targets: [XCActivityTarget],
            xcodeVersion: String?,
            status: ServerBuildRunStatus,
            ciRunId: String?,
            ciProjectHandle: String?,
            ciHost: String?,
            ciProvider: CIProvider?
        ) async throws -> ServerBuild
    }

    enum CreateBuildServiceError: LocalizedError {
        case unknownError(Int)
        case forbidden(String)
        case notFound(String)
        case unauthorized(String)
        case badRequest(String)
        case invalidURL(String)

        var errorDescription: String? {
            switch self {
            case let .unknownError(statusCode):
                return
                    "The build could not be uploaded due to an unknown server response of \(statusCode)."
            case let .forbidden(message), let .notFound(message), let .unauthorized(message),
                 let .badRequest(message):
                return message
            case let .invalidURL(url):
                return "Invalid URL for the build: \(url)."
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

        // swiftlint:disable:next function_body_length
        public func createBuild(
            fullHandle: String,
            serverURL: URL,
            id: String,
            category: XCActivityBuildCategory,
            configuration: String?,
            duration: Int,
            files: [XCActivityBuildFile],
            gitBranch: String?,
            gitCommitSHA: String?,
            gitRef: String?,
            gitRemoteURLOrigin: String?,
            isCI: Bool,
            issues: [XCActivityIssue],
            modelIdentifier: String?,
            macOSVersion: String,
            scheme: String?,
            targets: [XCActivityTarget],
            xcodeVersion: String?,
            status: ServerBuildRunStatus,
            ciRunId: String?,
            ciProjectHandle: String?,
            ciHost: String?,
            ciProvider: CIProvider?
        ) async throws -> ServerBuild {
            let client = Client.authenticated(serverURL: serverURL)
            let handles = try fullHandleService.parse(fullHandle)
            let status: Operations.createRun.Input.Body.jsonPayload.Case1Payload.statusPayload? =
                switch status {
                case .success:
                    .success
                case .failure:
                    .failure
                }

            let category: Operations.createRun.Input.Body.jsonPayload.Case1Payload.categoryPayload =
                switch category {
                case .clean:
                    .clean
                case .incremental:
                    .incremental
                }

            let ciProviderPayload: Operations.createRun.Input.Body.jsonPayload.Case1Payload.ci_providerPayload? =
                switch ciProvider {
                case .github:
                    .github
                case .gitlab:
                    .gitlab
                case .bitrise:
                    .bitrise
                case .circleci:
                    .circleci
                case .buildkite:
                    .buildkite
                case .codemagic:
                    .codemagic
                case .none:
                    nil
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
                                category: category,
                                ci_host: ciHost,
                                ci_project_handle: ciProjectHandle,
                                ci_provider: ciProviderPayload,
                                ci_run_id: ciRunId,
                                configuration: configuration,
                                duration: duration,
                                files: files
                                    .map(Operations.createRun.Input.Body.jsonPayload.Case1Payload.filesPayloadPayload.init),
                                git_branch: gitBranch,
                                git_commit_sha: gitCommitSHA,
                                git_ref: gitRef,
                                git_remote_url_origin: gitRemoteURLOrigin,
                                id: id,
                                is_ci: isCI,
                                issues: issues
                                    .map(Operations.createRun.Input.Body.jsonPayload.Case1Payload.issuesPayloadPayload.init),
                                macos_version: macOSVersion,
                                model_identifier: modelIdentifier,
                                scheme: scheme,
                                status: status,
                                targets: targets
                                    .map(Operations.createRun.Input.Body.jsonPayload.Case1Payload.targetsPayloadPayload.init),
                                xcode_version: xcodeVersion
                            )
                        )
                    )
                )
            )
            switch response {
            case let .ok(okResponse):
                switch okResponse.body {
                case let .json(run):
                    switch run {
                    case let .RunsBuild(build):
                        guard let build = ServerBuild(build) else { throw CreateBuildServiceError.invalidURL(build.url) }
                        return build
                    }
                }
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

    extension Operations.createRun.Input.Body.jsonPayload.Case1Payload.issuesPayloadPayload {
        fileprivate init(_ issue: XCActivityIssue) {
            let stepType:
                Operations.createRun.Input.Body.jsonPayload.Case1Payload.issuesPayloadPayload
                .step_typePayload =
                    switch issue.stepType {
                    case .XIBCompilation: .xib_compilation
                    case .cCompilation: .c_compilation
                    case .swiftCompilation: .swift_compilation
                    case .scriptExecution: .script_execution
                    case .createStaticLibrary: .create_static_library
                    case .linker: .linker
                    case .copySwiftLibs: .copy_swift_libs
                    case .compileAssetsCatalog: .compile_assets_catalog
                    case .compileStoryboard: .compile_storyboard
                    case .writeAuxiliaryFile: .write_auxiliary_file
                    case .linkStoryboards: .link_storyboards
                    case .copyResourceFile: .copy_resource_file
                    case .mergeSwiftModule: .merge_swift_module
                    case .swiftAggregatedCompilation: .swift_aggregated_compilation
                    case .precompileBridgingHeader: .precompile_bridging_header
                    case .validateEmbeddedBinary: .validate_embedded_binary
                    case .validate: .validate
                    case .other: .other
                    }
            let type: Operations.createRun.Input.Body.jsonPayload.Case1Payload.issuesPayloadPayload
                ._typePayload = switch issue.type
            {
            case .warning: .warning
            case .error: .error
            }
            self.init(
                ending_column: issue.endingColumn,
                ending_line: issue.endingLine,
                message: issue.message,
                path: issue.path?.pathString,
                project: issue.project,
                signature: issue.signature,
                starting_column: issue.startingColumn,
                starting_line: issue.startingLine,
                step_type: stepType,
                target: issue.target,
                title: issue.title,
                _type: type
            )
        }
    }

    extension Operations.createRun.Input.Body.jsonPayload.Case1Payload.filesPayloadPayload {
        fileprivate init(_ file: XCActivityBuildFile) {
            let fileType: Self._typePayload = switch file.type {
            case .c: .c
            case .swift: .swift
            }
            self.init(
                compilation_duration: file.compilationDuration,
                path: file.path.pathString,
                project: file.project,
                target: file.target,
                _type: fileType
            )
        }
    }

    extension Operations.createRun.Input.Body.jsonPayload.Case1Payload.targetsPayloadPayload {
        fileprivate init(_ target: XCActivityTarget) {
            let status: Self.statusPayload = switch target.status {
            case .failure: .failure
            case .success: .success
            }
            self.init(
                build_duration: target.buildDuration,
                compilation_duration: target.compilationDuration,
                name: target.name,
                project: target.project,
                status: status
            )
        }
    }

#endif
