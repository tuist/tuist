import Foundation
import Mockable
import Testing
import TuistNooraTesting
import TuistServer
@testable import TuistRunnerCommand

struct RunnerVolumeAnalyticsCommandServiceTests {
    @Test(.withMockedNoora, arguments: [false, true])
    func forwardsResolvedContextAndRendersResponse(json: Bool) async throws {
        let service = MockGetRunnerVolumeAnalyticsServicing()
        let response: RunnerVolumeAnalytics = try RunnerVolumeTestData.decode("""
        {"period":{"start":"2026-01-01T00:00:00Z","end":"2026-01-02T00:00:00Z"},
         "activity":{"hit_rate":null,"job_runs":0,"points":[]},
         "previous_activity":{"hit_rate":null,"job_runs":0,"points":[]},"storage":[],
         "trends":{"hit_rate_percentage_points":null,"used_bytes":{},"volumes":{}}}
        """)
        given(service).getRunnerVolumeAnalytics(
            accountHandle: .value("resolved-account"),
            serverURL: .value(StubRunnerVolumeContextService.serverURL),
            volumeID: .value(RunnerVolumeTestData.id),
            start: .value(nil),
            end: .value(nil)
        ).willReturn(response)
        let subject = RunnerVolumeAnalyticsCommandService(
            contextService: StubRunnerVolumeContextService(),
            getRunnerVolumeAnalyticsService: service
        )

        try await subject.run(
            volumeID: RunnerVolumeTestData.id,
            account: "explicit-account",
            path: "/project",
            start: nil,
            end: nil,
            json: json
        )

        verify(service).getRunnerVolumeAnalytics(
            accountHandle: .value("resolved-account"),
            serverURL: .value(StubRunnerVolumeContextService.serverURL),
            volumeID: .value(RunnerVolumeTestData.id),
            start: .value(nil),
            end: .value(nil)
        ).called(1)
        #expect(ui().contains(json ? "previous_activity" : "Cache hit rate: Not available"))
    }
}
