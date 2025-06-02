import Foundation
import Mockable
import OpenAPIURLSession

#if canImport(TuistSupport)
    import TuistSupport
    import TuistXCActivityLog

    @Mockable
    public protocol CreateBuildServicing {
        func createBuild(
            fullHandle: String,
            serverURL: URL,
            id: String,
            category: XCActivityBuildCategory,
            duration: Int,
            gitBranch: String?,
            gitCommitSHA: String?,
            isCI: Bool,
            issues: [XCActivityIssue],
            modelIdentifier: String?,
            macOSVersion: String,
            scheme: String?,
            xcodeVersion: String?,
            status: ServerBuildRunStatus
        ) async throws
    }

    enum CreateBuildServiceError: LocalizedError {
        case unknownError(Int)
        case forbidden(String)
        case notFound(String)
        case unauthorized(String)
        case badRequest(String)

        var errorDescription: String? {
            switch self {
            case let .unknownError(statusCode):
                return
                    "The build could not be uploaded due to an unknown server response of \(statusCode)."
            case let .forbidden(message), let .notFound(message), let .unauthorized(message),
                 let .badRequest(message):
                return message
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

        public func createBuild(
            fullHandle: String,
            serverURL: URL,
            id: String,
            category: XCActivityBuildCategory,
            duration: Int,
            gitBranch: String?,
            gitCommitSHA: String?,
            isCI: Bool,
            issues: [XCActivityIssue],
            modelIdentifier: String?,
            macOSVersion: String,
            scheme: String?,
            xcodeVersion: String?,
            status: ServerBuildRunStatus
        ) async throws {
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
                                duration: duration,
                                git_branch: gitBranch,
                                git_commit_sha: gitCommitSHA,
                                id: id,
                                is_ci: isCI,
                                issues: issues
                                    .map(Operations.createRun.Input.Body.jsonPayload.Case1Payload.issuesPayloadPayload.init),
                                macos_version: macOSVersion,
                                model_identifier: modelIdentifier,
                                scheme: scheme,
                                status: status,
                                xcode_version: xcodeVersion
                            )
                        )
                    )
                )
            )
            switch response {
            case .ok:
                break
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

#endif

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
