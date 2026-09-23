import Foundation
import Noora
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
    private let contextService: RunnerVolumeContextServicing
    private let listRunnerVolumesService: ListRunnerVolumesServicing

    init(
        contextService: RunnerVolumeContextServicing = RunnerVolumeContextService(),
        listRunnerVolumesService: ListRunnerVolumesServicing = ListRunnerVolumesService()
    ) {
        self.contextService = contextService
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
        let context = try await contextService.resolve(account: account, path: path)
        let response = try await listRunnerVolumesService.listRunnerVolumes(
            accountHandle: context.accountHandle,
            serverURL: context.serverURL,
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
                    accountHandle: context.accountHandle,
                    serverURL: context.serverURL,
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
