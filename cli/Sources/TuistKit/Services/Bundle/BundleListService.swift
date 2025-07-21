import Foundation
import OpenAPIURLSession
import Path
import TuistLoader
import TuistServer
import TuistSupport

protocol BundleListServicing {
    func run(
        fullHandle: String,
        path: String?,
        gitBranch: String?,
        json: Bool
    ) async throws
}

enum BundleListServiceError: Equatable, FatalError, LocalizedError {
    case missingFullHandle
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)

    var type: TuistSupport.ErrorType {
        switch self {
        case .missingFullHandle: .abort
        case .unknownError, .unauthorized, .forbidden: .abort
        }
    }

    var description: String {
        switch self {
        case .missingFullHandle:
            return "We couldn't list bundles because the full handle is missing. You can pass either its value or a path to a Tuist project."
        case let .unknownError(statusCode):
            return "The bundles could not be listed due to an unknown Tuist response of \(statusCode)."
        case let .unauthorized(message):
            return message
        case let .forbidden(message):
            return message
        }
    }

    var errorDescription: String? { description }
}

final class BundleListService: BundleListServicing {
    private let listBundlesService: ListBundlesServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        listBundlesService: ListBundlesServicing = ListBundlesService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.listBundlesService = listBundlesService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        fullHandle: String,
        path: String?,
        gitBranch: String?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath
        if let path {
            directoryPath = try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            directoryPath = FileHandler.shared.currentPath
        }

        let config = try await configLoader.loadConfig(path: directoryPath)
        let resolvedFullHandle = fullHandle.isEmpty ? config.fullHandle : fullHandle

        guard let resolvedFullHandle else {
            throw BundleListServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let bundles = try await listBundlesService.listBundles(
            fullHandle: resolvedFullHandle,
            gitBranch: gitBranch,
            page: nil,
            pageSize: 50,
            serverURL: serverURL
        )

        if json {
            // Create a raw response that matches the API format
            let rawBundles = bundles.map { bundle in
                [
                    "id": bundle.id,
                    "name": bundle.name,
                    "app_bundle_id": bundle.appBundleId,
                    "version": bundle.version,
                    "supported_platforms": bundle.supportedPlatforms,
                    "install_size": bundle.installSize,
                    "download_size": bundle.downloadSize as Any,
                    "git_branch": bundle.gitBranch as Any,
                    "git_commit_sha": bundle.gitCommitSha as Any,
                    "git_ref": bundle.gitRef as Any,
                    "inserted_at": Int(bundle.insertedAt.timeIntervalSince1970),
                    "updated_at": Int(bundle.updatedAt.timeIntervalSince1970),
                    "uploaded_by_account": bundle.uploadedByAccount,
                    "url": bundle.url,
                ]
            }
            let jsonData = try JSONSerialization.data(withJSONObject: rawBundles, options: .prettyPrinted)
            Logger.current.info(.init(stringLiteral: String(data: jsonData, encoding: .utf8)!), metadata: .json)
            return
        }

        if bundles.isEmpty {
            let branchFilter = gitBranch.map { " for branch '\($0)'" } ?? ""
            Logger.current.info("No bundles found for project \(resolvedFullHandle)\(branchFilter).")
            return
        }

        let bundlesString = formatBundlesList(bundles, fullHandle: resolvedFullHandle)
        Logger.current.info("\(bundlesString)")
    }

    private func formatBundlesList(_ bundles: [ServerBundle], fullHandle: String) -> String {
        let header = "Bundles for \(fullHandle):\n"
        let bundleLines = bundles.map { bundle in
            let installSizeFormatted = formatBytes(bundle.installSize)
            let downloadSizeFormatted = bundle.downloadSize.map(formatBytes) ?? "Unknown"
            let platforms = bundle.supportedPlatforms.joined(separator: ", ")
            let branch = bundle.gitBranch ?? "unknown"

            return "  • \(bundle.name) v\(bundle.version) (\(bundle.appBundleId))\n" +
                "    Platforms: \(platforms)\n" +
                "    Install Size: \(installSizeFormatted), Download Size: \(downloadSizeFormatted)\n" +
                "    Branch: \(branch)\n" +
                "    ID: \(bundle.id)"
        }

        return header + bundleLines.joined(separator: "\n\n")
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
