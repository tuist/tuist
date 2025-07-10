import Foundation
import Path
import TuistLoader
import TuistServer
import TuistSupport

protocol BundleListServicing {
    func run(
        json: Bool,
        directory: String?,
        gitBranch: String?,
        page: Int?,
        pageSize: Int?
    ) async throws
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
        json: Bool,
        directory: String?,
        gitBranch: String?,
        page: Int?,
        pageSize: Int?
    ) async throws {
        let directoryPath: AbsolutePath
        if let directory {
            directoryPath = try AbsolutePath(
                validating: directory, relativeTo: FileHandler.shared.currentPath
            )
        } else {
            directoryPath = FileHandler.shared.currentPath
        }
        let config = try await configLoader.loadConfig(path: directoryPath)
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let bundleListResponse = try await listBundlesService.listBundles(
            serverURL: serverURL,
            fullHandle: config.fullHandle,
            gitBranch: gitBranch,
            page: page,
            pageSize: pageSize
        )

        if json {
            let json = bundleListResponse.toJSON()
            Logger.current.info(
                .init(stringLiteral: json.toString(prettyPrint: true)), metadata: .json
            )
            return
        }

        if bundleListResponse.bundles.isEmpty {
            var message = "No bundles found for this project."
            if let gitBranch {
                message += " (filtered by git branch: \(gitBranch))"
            }
            Logger.current.info(message)
            return
        }

        let bundlesInfo = bundleListResponse.bundles.map { bundle in
            var info = "  • \(bundle.name) (v\(bundle.version))"
            if let gitBranch = bundle.gitBranch {
                info += " - \(gitBranch)"
            }
            info += " - \(formatBytes(bundle.installSize))"
            if let insertedAt = bundle.insertedAt {
                info += " - \(insertedAt.formatted(date: .abbreviated, time: .shortened))"
            }
            return info
        }

        var output = "Listing bundles:\n" + bundlesInfo.joined(separator: "\n")
        
        if let meta = bundleListResponse.meta {
            output += "\n\nPage \(page ?? 1) of bundles"
            if meta.hasNextPage {
                output += " (has more)"
            }
            output += " - Total: \(meta.totalCount)"
        }

        Logger.current.info("\(output)")
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}