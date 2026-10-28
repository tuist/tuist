import Foundation
import Mockable
import Testing
import TuistEnvironmentTesting
import TuistNooraTesting
import TuistServer
@testable import TuistRunnerCommand

struct RunnerVolumeJobsCommandServiceTests {
    @Test(.withMockedEnvironment(), .withMockedNoora, arguments: [false, true])
    func forwardsResolvedContextAndRendersResponse(json: Bool) async throws {
        let service = MockListRunnerVolumeJobsServicing()
        let response: RunnerVolumeJobsPage = try RunnerVolumeTestData
            .decode(
                "{\"jobs\":[{\"id\":\"use-id\",\"workflow_job_id\":1024,\"workflow_run_id\":500,\"job_name\":\"Build\",\"workflow_name\":\"CI\",\"cache_status\":\"saved\",\"cache_status_description\":\"Saved for future runs.\",\"cache_hit\":false}],\"pagination_metadata\":\(RunnerVolumeTestData.pagination)}"
            )
        given(service).listRunnerVolumeJobs(
            accountHandle: .value("resolved-account"),
            serverURL: .value(RunnerVolumeTestData.serverURL),
            volumeID: .value(RunnerVolumeTestData.id),
            page: .value(2),
            pageSize: .value(5)
        ).willReturn(response)
        let subject = RunnerVolumeJobsCommandService(
            configLoader: try await RunnerVolumeTestData.configLoader(),
            serverEnvironmentService: RunnerVolumeTestData.serverEnvironmentService(),
            listRunnerVolumeJobsService: service
        )

        try await subject.run(
            volumeID: RunnerVolumeTestData.id,
            account: nil,
            path: "/project",
            page: 2,
            pageSize: 5,
            json: json
        )

        verify(service).listRunnerVolumeJobs(
            accountHandle: .value("resolved-account"),
            serverURL: .value(RunnerVolumeTestData.serverURL),
            volumeID: .value(RunnerVolumeTestData.id),
            page: .value(2),
            pageSize: .value(5)
        ).called(1)
        #expect(ui().contains(json ? "pagination_metadata" : "Miss"))
    }
}
