import Foundation
import Noora
import TuistConfigLoader
import TuistEnvironment
import TuistHTTP
import TuistServer

protocol RunnerVolumeJobsCommandServicing {
    func run(volumeID: String, account: String?, path: String?, page: Int, pageSize: Int, json: Bool) async throws
}

enum RunnerVolumeJobsCommandServiceError: LocalizedError, Equatable {
    case missingAccount

    var errorDescription: String? {
        "Pass --account or configure a project full handle."
    }
}

struct RunnerVolumeJobsCommandService: RunnerVolumeJobsCommandServicing {
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let fullHandleService: FullHandleServicing
    private let listRunnerVolumeJobsService: ListRunnerVolumeJobsServicing

    init(
        configLoader: ConfigLoading = ConfigLoader(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        fullHandleService: FullHandleServicing = FullHandleService(),
        listRunnerVolumeJobsService: ListRunnerVolumeJobsServicing = ListRunnerVolumeJobsService()
    ) {
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
        self.fullHandleService = fullHandleService
        self.listRunnerVolumeJobsService = listRunnerVolumeJobsService
    }

    func run(volumeID: String, account: String?, path: String?, page: Int, pageSize: Int, json: Bool) async throws {
        let directory = try await Environment.current.pathRelativeToWorkingDirectory(path)
        let config = try await configLoader.loadConfig(path: directory)
        guard let accountHandle = try account ?? config.fullHandle.map({ try fullHandleService.parse($0).accountHandle }),
              !accountHandle.isEmpty
        else {
            throw RunnerVolumeJobsCommandServiceError.missingAccount
        }
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)
        let response = try await listRunnerVolumeJobsService.listRunnerVolumeJobs(
            accountHandle: accountHandle,
            serverURL: serverURL,
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
                    accountHandle: accountHandle,
                    serverURL: serverURL,
                    volumeID: volumeID,
                    page: pageIndex + 1,
                    pageSize: pageSize
                )
                return nextPage.jobs.map(RunnerVolumeOutput.jobRow)
            }
        )
    }
}
