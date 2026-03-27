import Foundation
import Noora
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistNooraExtension
import TuistServer

protocol BundleArtifactListCommandServicing {
    func run(
        bundleId: String,
        fullHandle: String?,
        path: String?,
        pageSize: Int?,
        json: Bool
    ) async throws
}

enum BundleArtifactListCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't list bundle artifacts because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

struct BundleArtifactListCommandService: BundleArtifactListCommandServicing {
    private let getBundleArtifactTreeService: GetBundleArtifactTreeServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        getBundleArtifactTreeService: GetBundleArtifactTreeServicing = GetBundleArtifactTreeService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.getBundleArtifactTreeService = getBundleArtifactTreeService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        bundleId: String,
        fullHandle: String?,
        path: String?,
        pageSize: Int?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = fullHandle ?? config.fullHandle else {
            throw BundleArtifactListCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let response = try await getBundleArtifactTreeService.getBundleArtifactTree(
            fullHandle: resolvedFullHandle,
            serverURL: serverURL,
            bundleId: bundleId
        )

        if json {
            try Noora.current.json(response.artifacts)
            return
        }

        if response.artifacts.isEmpty {
            Noora.current.passthrough("No artifacts found for bundle \(bundleId).")
            return
        }

        try Noora.current.paginatedTable(TableData(columns: [
            TableColumn(title: "Type", width: .auto),
            TableColumn(title: "Path", width: .auto),
            TableColumn(title: "Size", width: .auto),
        ], rows: response.artifacts.map { artifact in
            [
                "\(artifact.artifact_type)",
                "\(artifact.path)",
                "\(Formatters.formatBytes(artifact.size))",
            ]
        }), pageSize: pageSize ?? 50)
    }
}
