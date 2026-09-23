import Foundation
import Noora
import TuistServer

protocol RunnerVolumeJobsCommandServicing {
    func run(volumeID: String, account: String?, path: String?, page: Int, pageSize: Int, json: Bool) async throws
}

struct RunnerVolumeJobsCommandService: RunnerVolumeJobsCommandServicing {
    private let contextService: RunnerVolumeContextServicing
    private let listRunnerVolumeJobsService: ListRunnerVolumeJobsServicing

    init(
        contextService: RunnerVolumeContextServicing = RunnerVolumeContextService(),
        listRunnerVolumeJobsService: ListRunnerVolumeJobsServicing = ListRunnerVolumeJobsService()
    ) {
        self.contextService = contextService
        self.listRunnerVolumeJobsService = listRunnerVolumeJobsService
    }

    func run(volumeID: String, account: String?, path: String?, page: Int, pageSize: Int, json: Bool) async throws {
        let context = try await contextService.resolve(account: account, path: path)
        let response = try await listRunnerVolumeJobsService.listRunnerVolumeJobs(
            accountHandle: context.accountHandle,
            serverURL: context.serverURL,
            volumeID: volumeID,
            page: page,
            pageSize: pageSize
        )
        if json {
            try Noora.current.json(response)
            return
        }
        guard !response.jobs.isEmpty else {
            Noora.current.passthrough("No jobs found on page \(page) for this volume.")
            return
        }
        try await Noora.current.paginatedTable(
            headers: ["ID", "Job", "Workflow", "Cache status", "Cache", "Used space", "Mounted at"],
            pageSize: pageSize,
            totalPages: response.pagination_metadata.total_pages,
            startPage: page - 1,
            loadPage: { pageIndex in
                if pageIndex == page - 1 { return response.jobs.map(RunnerVolumeOutput.jobRow) }
                let nextPage = try await listRunnerVolumeJobsService.listRunnerVolumeJobs(
                    accountHandle: context.accountHandle,
                    serverURL: context.serverURL,
                    volumeID: volumeID,
                    page: pageIndex + 1,
                    pageSize: pageSize
                )
                return nextPage.jobs.map(RunnerVolumeOutput.jobRow)
            }
        )
    }
}
