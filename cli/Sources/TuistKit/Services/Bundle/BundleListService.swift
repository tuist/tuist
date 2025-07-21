import Foundation
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

enum BundleListServiceError: Equatable, FatalError {
    case missingFullHandle

    var type: TuistSupport.ErrorType {
        switch self {
        case .missingFullHandle: .abort
        }
    }

    var description: String {
        switch self {
        case .missingFullHandle:
            return "We couldn't list bundles because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
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
            let jsonData = try bundles.toJSON()
            Logger.current.info(.init(stringLiteral: jsonData.toString(prettyPrint: true)), metadata: .json)
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
            let downloadSizeFormatted = formatBytes(bundle.downloadSize)
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
