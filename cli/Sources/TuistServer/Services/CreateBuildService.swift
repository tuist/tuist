import Foundation
import Mockable
import OpenAPIURLSession
import TuistHTTP

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
            ciProvider: CIProvider?,
            cacheableTasks: [CacheableTask],
            casOutputs: [CASOutput]
        ) async throws -> ServerBuild
    }

    enum CreateBuildServiceError: LocalizedError {
        case unknownError(Int)
        case forbidden(String)
        case notFound(String)
        case unauthorized(String)
        case badRequest(String)
        case invalidURL(String)
        case unexpectedResponseType

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
            case .unexpectedResponseType:
                return "The server returned an unexpected response type. Expected a build run but received a different type."
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
            ciProvider: CIProvider?,
            cacheableTasks: [CacheableTask],
            casOutputs: [CASOutput]
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
                                cacheable_tasks: cacheableTasks
                                    .map(Operations.createRun.Input.Body.jsonPayload.Case1Payload.cacheable_tasksPayloadPayload
                                        .init
                                    ),
                                cas_outputs: casOutputs
                                    .map(Operations.createRun.Input.Body.jsonPayload.Case1Payload.cas_outputsPayloadPayload.init),
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
                                _type: .build,
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
                    case .RunsTest:
                        throw CreateBuildServiceError.unexpectedResponseType
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

    extension Operations.createRun.Input.Body.jsonPayload.Case1Payload.cacheable_tasksPayloadPayload {
        fileprivate init(_ cacheableTask: CacheableTask) {
            let taskType: Self._typePayload = switch cacheableTask.type {
            case .swift: .swift
            case .clang: .clang
            }
            let status: Self.statusPayload = switch cacheableTask.status {
            case .localHit: .hit_local
            case .remoteHit: .hit_remote
            case .miss: .miss
            }
            self.init(
                cas_output_node_ids: cacheableTask.nodeIDs,
                description: cacheableTask.description,
                key: cacheableTask.key,
                read_duration: cacheableTask.readDuration,
                status: status,
                _type: taskType,
                write_duration: cacheableTask.writeDuration
            )
        }
    }

    extension Operations.createRun.Input.Body.jsonPayload.Case1Payload.cas_outputsPayloadPayload {
        fileprivate init(_ casOutput: CASOutput) {
            let operation: Self.operationPayload = switch casOutput.operation {
            case .download: .download
            case .upload: .upload
            }
            let type: Self._typePayload? = switch casOutput.type {
            case .swift: .swift
            case .sil: .sil
            case .sib: .sib
            case .image: .image
            case .object: .object
            case .dSYM: .dSYM
            case .dependencies: .dependencies
            case .autolink: .autolink
            case .swiftModule: .swiftmodule
            case .swiftDocumentation: .swiftdoc
            case .swiftInterface: .swiftinterface
            case .privateSwiftInterface: .private_hyphen_swiftinterface
            case .packageSwiftInterface: .package_hyphen_swiftinterface
            case .swiftSourceInfoFile: .swiftsourceinfo
            case .swiftConstValues: .const_hyphen_values
            case .assembly: .assembly
            case .rawSil: .raw_hyphen_sil
            case .rawSib: .raw_hyphen_sib
            case .rawLlvmIr: .raw_hyphen_llvm_hyphen_ir
            case .llvmIR: .llvm_hyphen_ir
            case .llvmBitcode: .llvm_hyphen_bc
            case .diagnostics: .diagnostics
            case .emitModuleDiagnostics: .emit_hyphen_module_hyphen_diagnostics
            case .dependencyScanDiagnostics: .dependency_hyphen_scan_hyphen_diagnostics
            case .emitModuleDependencies: .emit_hyphen_module_hyphen_dependencies
            case .objcHeader: .objc_hyphen_header
            case .swiftDeps: .swift_hyphen_dependencies
            case .modDepCache: .dependency_hyphen_scanner_hyphen_cache
            case .remap: .remap
            case .importedModules: .imported_hyphen_modules
            case .tbd: .tbd
            case .jsonDependencies: .json_hyphen_dependencies
            case .jsonTargetInfo: .json_hyphen_target_hyphen_info
            case .jsonCompilerFeatures: .json_hyphen_supported_hyphen_features
            case .jsonSupportedFeatures: .json_hyphen_supported_hyphen_swift_hyphen_features
            case .jsonSwiftArtifacts: .json_hyphen_module_hyphen_artifacts
            case .moduleTrace: .module_hyphen_trace
            case .indexData: .index_hyphen_data
            case .indexUnitOutputPath: .index_hyphen_unit_hyphen_output_hyphen_path
            case .yamlOptimizationRecord: .yaml_hyphen_opt_hyphen_record
            case .bitstreamOptimizationRecord: .bitstream_hyphen_opt_hyphen_record
            case .pcm: .pcm
            case .pch: .pch
            case .clangModuleMap: .modulemap
            case .jsonAPIBaseline: .api_hyphen_baseline_hyphen_json
            case .jsonABIBaseline: .abi_hyphen_baseline_hyphen_json
            case .jsonAPIDescriptor: .api_hyphen_descriptor_hyphen_json
            case .moduleSummary: .swift_hyphen_module_hyphen_summary
            case .moduleSemanticInfo: .module_hyphen_semantic_hyphen_info
            case .cachedDiagnostics: .cached_hyphen_diagnostics
            case .localizationStrings: .localization_hyphen_strings
            case .clangHeader: .clang_hyphen_header
            }
            self.init(
                checksum: casOutput.checksum,
                compressed_size: casOutput.compressedSize,
                duration: casOutput.duration,
                node_id: casOutput.nodeID,
                operation: operation,
                size: casOutput.size,
                _type: type
            )
        }
    }

#endif
