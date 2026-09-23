import Foundation
import Mockable
import Testing
import TuistNooraTesting
import TuistServer
@testable import TuistRunnerCommand

struct RunnerVolumeShowCommandServiceTests {
    @Test(.withMockedNoora, arguments: [false, true])
    func forwardsResolvedContextAndRendersResponse(json: Bool) async throws {
        let service = MockGetRunnerVolumeServicing()
        let response: RunnerVolume = try RunnerVolumeTestData.decode(RunnerVolumeTestData.volume)
        given(service).getRunnerVolume(
            accountHandle: .value("resolved-account"),
            serverURL: .value(StubRunnerVolumeContextService.serverURL),
            volumeID: .value(RunnerVolumeTestData.id)
        ).willReturn(response)
        let subject = RunnerVolumeShowCommandService(
            contextService: StubRunnerVolumeContextService(),
            getRunnerVolumeService: service
        )

        try await subject.run(volumeID: RunnerVolumeTestData.id, account: "explicit-account", path: "/project", json: json)

        verify(service).getRunnerVolume(
            accountHandle: .value("resolved-account"),
            serverURL: .value(StubRunnerVolumeContextService.serverURL),
            volumeID: .value(RunnerVolumeTestData.id)
        ).called(1)
        #expect(ui().contains(json ? "capacity_bytes" : "Capacity: 20 GB"))
    }
}
