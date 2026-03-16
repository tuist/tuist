import Foundation
import Noora
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistNooraExtension
import TuistServer

protocol BuildXcodeFileListCommandServicing {
    func run(
        fullHandle: String?,
        buildId: String,
        path: String?,
        target: String?,
        fileType: String?,
        sortBy: String?,
        page: Int?,
        pageSize: Int?,
        json: Bool
    ) async throws
}

enum BuildXcodeFileListCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't list the build files because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

struct BuildXcodeFileListCommandService: BuildXcodeFileListCommandServicing {
    private let listBuildFilesService: ListBuildFilesServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        listBuildFilesService: ListBuildFilesServicing = ListBuildFilesService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.listBuildFilesService = listBuildFilesService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        fullHandle: String?,
        buildId: String,
        path: String?,
        target: String?,
        fileType: String?,
        sortBy: String?,
        page: Int?,
        pageSize: Int?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = fullHandle ?? config.fullHandle else {
            throw BuildXcodeFileListCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let startPage = (page ?? 1) - 1
        let pageSize = pageSize ?? 10

        let initialPage = try await listBuildFilesService.listBuildFiles(
            fullHandle: resolvedFullHandle,
            serverURL: serverURL,
            buildId: buildId,
            target: target,
            type: fileType,
            sortBy: sortBy,
            page: startPage + 1,
            pageSize: pageSize
        )

        let files = initialPage.files

        if json {
            try Noora.current.json(files)
            return
        }

        if files.isEmpty {
            Noora.current.passthrough("No files found for build \(buildId).")
            return
        }

        let totalPages = initialPage.pagination_metadata.total_pages ?? 1

        let initialRows = files.map { file in
            [
                file.path,
                file.target,
                file._type.rawValue,
                Formatters.formatDuration(file.compilation_duration),
            ]
        }

        try await Noora.current.paginatedTable(
            headers: ["Path", "Target", "Type", "Duration"],
            pageSize: pageSize,
            totalPages: totalPages,
            startPage: startPage,
            loadPage: { [self] pageIndex in
                if pageIndex == startPage {
                    return initialRows
                }
                let filePage = try await listBuildFilesService.listBuildFiles(
                    fullHandle: resolvedFullHandle,
                    serverURL: serverURL,
                    buildId: buildId,
                    target: target,
                    type: fileType,
                    sortBy: sortBy,
                    page: pageIndex + 1,
                    pageSize: pageSize
                )
                return filePage.files.map { file in
                    [
                        file.path,
                        file.target,
                        file._type.rawValue,
                        Formatters.formatDuration(file.compilation_duration),
                    ]
                }
            }
        )
    }
}
