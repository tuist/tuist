import TuistHTTP
#if canImport(Rosalind)
    import Foundation
    import Mockable
    import OpenAPIURLSession
    import Path
    import Rosalind

    @Mockable
    public protocol CreateBundleServicing {
        func createBundle(
            fullHandle: String,
            serverURL: URL,
            appBundleReport: AppBundleReport,
            gitCommitSHA: String?,
            gitBranch: String?,
            gitRef: String?
        ) async throws -> Components.Schemas.Bundle
    }

    enum CreateBundleServiceError: LocalizedError {
        case unknownError(Int)
        case forbidden(String)
        case notFound(String)
        case unauthorized(String)
        case badRequest(String)
        case unknownPlatform(String)
        case invalidBundle(String)

        var errorDescription: String? {
            switch self {
            case let .unknownError(statusCode):
                return "The bundle could not be uploaded due to an unknown server response of \(statusCode)."
            case let .forbidden(message), let .notFound(message), let .unauthorized(message), let .badRequest(message):
                return message
            case let .unknownPlatform(platform):
                return "The \(platform) found in the app bundle is unknonw."
            case let .invalidBundle(id):
                return "The bundle \(id) is invalid."
            }
        }
    }

    public final class CreateBundleService: CreateBundleServicing {
        private let fullHandleService: FullHandleServicing

        public init(
            fullHandleService: FullHandleServicing = FullHandleService()
        ) {
            self.fullHandleService = fullHandleService
        }

        public func createBundle(
            fullHandle: String,
            serverURL: URL,
            appBundleReport: AppBundleReport,
            gitCommitSHA: String?,
            gitBranch: String?,
            gitRef: String?
        ) async throws -> Components.Schemas.Bundle {
            let client = Client.authenticated(serverURL: serverURL)
            let handles = try fullHandleService.parse(fullHandle)
            let supportedPlatforms: [Components.Schemas.BundleSupportedPlatform] = try appBundleReport.platforms.map {
                switch $0.lowercased() {
                case "appletvsimulator": .tvos_simulator
                case "appletvos": .tvos
                case "iphonesimulator": .ios_simulator
                case "iphoneos": .ios
                case "macosx": .macos
                case "watchsimulator": .watchos_simulator
                case "watchos": .watchos
                case "xrsimulator": .visionos_simulator
                case "xros": .visionos
                default:
                    throw CreateBundleServiceError.unknownPlatform($0)
                }
            }

            let bundleType: Operations.createBundle.Input.Body.jsonPayload.bundlePayload._typePayload = switch appBundleReport
                .type
            {
            case .ipa: .ipa
            case .app: .app
            case .xcarchive: .xcarchive
            }

            let response = try await client.createBundle(
                .init(
                    path: .init(
                        account_handle: handles.accountHandle,
                        project_handle: handles.projectHandle
                    ),
                    body: .json(
                        .init(
                            bundle: .init(
                                app_bundle_id: appBundleReport.bundleId,
                                artifacts: appBundleReport.artifacts.map { .init($0) },
                                download_size: appBundleReport.downloadSize,
                                git_branch: gitBranch,
                                git_commit_sha: gitCommitSHA,
                                git_ref: gitRef,
                                install_size: appBundleReport.installSize,
                                name: appBundleReport.name,
                                supported_platforms: supportedPlatforms,
                                _type: bundleType,
                                version: appBundleReport.version
                            )
                        )
                    )
                )
            )
            switch response {
            case let .ok(okResponse):
                switch okResponse.body {
                case let .json(bundle):
                    return bundle
                }
            case let .undocumented(statusCode: statusCode, _):
                throw CreateBundleServiceError.unknownError(statusCode)
            case let .badRequest(badRequestResponse):
                switch badRequestResponse.body {
                case let .json(error):
                    throw CreateBundleServiceError.badRequest(error.message)
                }
            case let .unauthorized(unauthorizedResponse):
                switch unauthorizedResponse.body {
                case let .json(error):
                    throw CreateBundleServiceError.unauthorized(error.message)
                }
            case let .forbidden(forbiddenResponse):
                switch forbiddenResponse.body {
                case let .json(error):
                    throw CreateBuildServiceError.forbidden(error.message)
                }
            }
        }
    }

    extension Components.Schemas.BundleArtifact {
        init(_ artifact: AppBundleArtifact) {
            let artifactType: Components.Schemas.BundleArtifact.artifact_typePayload = switch artifact.artifactType {
            case .directory: .directory
            case .file: .file
            case .font: .font
            case .binary: .binary
            case .localization: .localization
            case .asset: .asset
            }
            self.init(
                artifact_type: artifactType,
                children: artifact.children.map {
                    $0.map { Self($0) }
                },
                path: artifact.path,
                shasum: artifact.shasum,
                size: artifact.size
            )
        }
    }
#endif
