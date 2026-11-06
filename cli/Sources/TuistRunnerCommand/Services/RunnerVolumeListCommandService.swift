import Foundation
import Noora
import TuistConfigLoader
import TuistEnvironment
import TuistHTTP
import TuistServer

protocol RunnerVolumeListCommandServicing {
    func run(
        account: String?,
        path: String?,
        name: String?,
        repository: String?,
        sortBy: String?,
        sortOrder: String?,
        page: Int,
        pageSize: Int,
        json: Bool
    ) async throws
}

struct RunnerVolumeListCommandService: RunnerVolumeListCommandServicing {
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let fullHandleService: FullHandleServicing
    private let listRunnerVolumesService: ListRunnerVolumesServicing

    init(
        configLoader: ConfigLoading = ConfigLoader(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        fullHandleService: FullHandleServicing = FullHandleService(),
        listRunnerVolumesService: ListRunnerVolumesServicing = ListRunnerVolumesService()
    ) {
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
        self.fullHandleService = fullHandleService
        self.listRunnerVolumesService = listRunnerVolumesService
    }

    func run(
        account: String?,
        path: String?,
        name: String?,
        repository: String?,
        sortBy: String?,
        sortOrder: String?,
        page: Int,
        pageSize: Int,
        json: Bool
    ) async throws {
        let (accountHandle, serverURL) = try await RunnerAccount.resolve(
            account: account,
            path: path,
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService,
            fullHandleService: fullHandleService
        )
        let response = try await listRunnerVolumesService.listRunnerVolumes(
            accountHandle: accountHandle,
            serverURL: serverURL,
            name: name,
            repository: repository,
            sortBy: sortBy,
            sortOrder: sortOrder,
            page: page,
            pageSize: pageSize
        )
        if json {
            try Noora.current.json(response)
            return
        }
        guard !response.volumes.isEmpty else {
            Noora.current.passthrough("No volumes found on page \(page).")
            return
        }
        try await Noora.current.paginatedTable(
            headers: ["ID", "Volume", "Repository", "Platform", "Used space", "Capacity", "Last used"],
            pageSize: pageSize,
            totalPages: response.pagination_metadata.total_pages,
            startPage: page - 1,
            loadPage: { pageIndex in
                if pageIndex == page - 1 { return response.volumes.map(RunnerVolumeOutput.volumeRow) }
                let nextPage = try await listRunnerVolumesService.listRunnerVolumes(
                    accountHandle: accountHandle,
                    serverURL: serverURL,
                    name: name,
                    repository: repository,
                    sortBy: sortBy,
                    sortOrder: sortOrder,
                    page: pageIndex + 1,
                    pageSize: pageSize
                )
                return nextPage.volumes.map(RunnerVolumeOutput.volumeRow)
            }
        )
    }
}
