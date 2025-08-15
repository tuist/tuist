import Foundation
import Noora
import OpenAPIURLSession
import Path
import TuistLoader
import TuistServer
import TuistSupport

protocol BundleListCommandServicing {
    func run(
        fullHandle: String?,
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
        fullHandle: String?,
        path: String?,
        gitBranch: String?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = fullHandle != nil ? fullHandle! : config.fullHandle else {
            throw BundleListCommandServiceError.missingFullHandle
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
            try Noora.current.json(bundles)
            return
        }

        if bundles.isEmpty {
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
        ], rows: bundles.map { bundle in
            return [
                "\(bundle.id)",
                "\(bundle.appBundleId)",
                "\(Formatters.formatBytes(bundle.installSize))",
                "\(bundle.downloadSize != nil ? Formatters.formatBytes(bundle.downloadSize!) : "Unknown")",
                "\(Formatters.formatDate(bundle.insertedAt))",
                "\(.link(title: "Link", href: bundle.url))",
            ]
        }), pageSize: 10)
    }
}
