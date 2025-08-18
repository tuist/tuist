import Foundation
import Noora
import OpenAPIURLSession
import Path
import TuistLoader
import TuistServer
import TuistSupport

protocol BundleListCommandServicing {
    func run(
        project: String?,
        path: String?,
        gitBranch: String?,
        json: Bool
    ) async throws
}

enum BundleListCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't list bundles because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

final class BundleListCommandService: BundleListCommandServicing {
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
        project: String?,
        path: String?,
        gitBranch: String?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = project != nil ? project! : config.fullHandle else {
            throw BundleListCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let response = try await listBundlesService.listBundles(
            fullHandle: resolvedFullHandle,
            gitBranch: gitBranch,
            page: nil,
            pageSize: 50,
            serverURL: serverURL
        )

        if json {
            try Noora.current.json(response)
            return
        }

        if response.bundles.isEmpty {
            let branchFilter = gitBranch.map { " for branch '\($0)'" } ?? ""
            Noora.current.passthrough("No bundles found for project \(resolvedFullHandle)\(branchFilter).")
            return
        }

        try Noora.current.paginatedTable(TableData(columns: [
            TableColumn(title: "ID", width: .auto),
            TableColumn(title: "App bundle id", width: .auto),
            TableColumn(title: "Install size", width: .auto),
            TableColumn(title: "Download size", width: .auto),
            TableColumn(title: "Inserted at", width: .auto),
            TableColumn(title: "URL", width: .auto),
        ], rows: response.bundles.map { bundle in
            return [
                "\(bundle.id)",
                "\(bundle.app_bundle_id)",
                "\(Formatters.formatBytes(bundle.install_size))",
                "\(bundle.download_size != nil ? Formatters.formatBytes(bundle.download_size!) : "Unknown")",
                "\(Formatters.formatDate(bundle.inserted_at))",
                "\(.link(title: "Link", href: bundle.url))",
            ]
        }), pageSize: 10)
    }
}
