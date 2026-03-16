import Foundation
import Noora
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistNooraExtension
import TuistServer

protocol BuildXcodeTargetListCommandServicing {
    func run(
        fullHandle: String?,
        buildId: String,
        path: String?,
        status: String?,
        page: Int?,
        pageSize: Int?,
        json: Bool
    ) async throws
}

enum BuildXcodeTargetListCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't list the build targets because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

struct BuildXcodeTargetListCommandService: BuildXcodeTargetListCommandServicing {
    private let listBuildTargetsService: ListBuildTargetsServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        listBuildTargetsService: ListBuildTargetsServicing = ListBuildTargetsService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.listBuildTargetsService = listBuildTargetsService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        fullHandle: String?,
        buildId: String,
        path: String?,
        status: String?,
        page: Int?,
        pageSize: Int?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = fullHandle ?? config.fullHandle else {
            throw BuildXcodeTargetListCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let startPage = (page ?? 1) - 1
        let pageSize = pageSize ?? 10

        let initialPage = try await listBuildTargetsService.listBuildTargets(
            fullHandle: resolvedFullHandle,
            serverURL: serverURL,
            buildId: buildId,
            status: status,
            page: startPage + 1,
            pageSize: pageSize
        )

        let targets = initialPage.targets

        if json {
            try Noora.current.json(targets)
            return
        }

        if targets.isEmpty {
            Noora.current.passthrough("No targets found for build \(buildId).")
            return
        }

        let totalPages = initialPage.pagination_metadata.total_pages ?? 1

        let initialRows = targets.map { target in
            [
                target.name,
                target.status.rawValue,
                Formatters.formatDuration(target.build_duration),
            ]
        }

        try await Noora.current.paginatedTable(
            headers: ["Name", "Status", "Duration"],
            pageSize: pageSize,
            totalPages: totalPages,
            startPage: startPage,
            loadPage: { [self] pageIndex in
                if pageIndex == startPage {
                    return initialRows
                }
                let targetPage = try await listBuildTargetsService.listBuildTargets(
                    fullHandle: resolvedFullHandle,
                    serverURL: serverURL,
                    buildId: buildId,
                    status: status,
                    page: pageIndex + 1,
                    pageSize: pageSize
                )
                return targetPage.targets.map { target in
                    [
                        target.name,
                        target.status.rawValue,
                        Formatters.formatDuration(target.build_duration),
                    ]
                }
            }
        )
    }
}
