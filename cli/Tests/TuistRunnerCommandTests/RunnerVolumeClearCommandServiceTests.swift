import Foundation
import Mockable
import Testing
import TuistNooraTesting
import TuistServer
@testable import TuistRunnerCommand

struct RunnerVolumeClearCommandServiceTests {
    private enum TestError: Error { case forbidden }

    @Test(.withMockedNoora)
    func doesNotReportSuccessWhenServerRejectsClearing() async throws {
        let service = MockClearRunnerVolumeServicing()
        given(service).clearRunnerVolume(
            accountHandle: .any,
            serverURL: .any,
            volumeID: .any
        ).willThrow(TestError.forbidden)
        let subject = RunnerVolumeClearCommandService(
            contextService: StubRunnerVolumeContextService(),
            clearRunnerVolumeService: service
        )

        await #expect(throws: TestError.forbidden) {
            try await subject.run(
                volumeID: RunnerVolumeTestData.id,
                account: "explicit-account",
                path: "/project",
                json: false
            )
        }
        #expect(!ui().contains("Success"))
    }

    @Test(.withMockedNoora, arguments: [false, true])
    func forwardsResolvedContextAndRendersResponse(json: Bool) async throws {
        let service = MockClearRunnerVolumeServicing()
        let response: RunnerVolumeClearResult = try RunnerVolumeTestData
            .decode("{\"id\":\"\(RunnerVolumeTestData.id)\",\"cleared\":true}")
        given(service).clearRunnerVolume(
            accountHandle: .value("resolved-account"),
            serverURL: .value(StubRunnerVolumeContextService.serverURL),
            volumeID: .value(RunnerVolumeTestData.id)
        ).willReturn(response)
        let subject = RunnerVolumeClearCommandService(
            contextService: StubRunnerVolumeContextService(),
            clearRunnerVolumeService: service
        )

        try await subject.run(volumeID: RunnerVolumeTestData.id, account: "explicit-account", path: "/project", json: json)

        verify(service).clearRunnerVolume(
            accountHandle: .value("resolved-account"),
            serverURL: .value(StubRunnerVolumeContextService.serverURL),
            volumeID: .value(RunnerVolumeTestData.id)
        ).called(1)
        #expect(ui().contains(json ? "cleared" : "Saved contents cleared"))
    }
}
