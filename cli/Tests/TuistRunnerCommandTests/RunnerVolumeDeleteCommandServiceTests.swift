import Foundation
import Mockable
import TestCoverageAttribution
import Testing
import TuistEnvironmentTesting
import TuistNooraTesting
import TuistServer
@testable import TuistRunnerCommand

@Suite(.coverageAttribution)
struct RunnerVolumeDeleteCommandServiceTests {
    private enum TestError: Error { case forbidden }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func doesNotReportSuccessWhenServerRejectsDeletion() async throws {
        let service = MockDeleteRunnerVolumeServicing()
        given(service).deleteRunnerVolume(
            accountHandle: .any,
            serverURL: .any,
            volumeID: .any
        ).willThrow(TestError.forbidden)
        let subject = RunnerVolumeDeleteCommandService(
            configLoader: try await RunnerVolumeTestData.configLoader(),
            serverEnvironmentService: RunnerVolumeTestData.serverEnvironmentService(),
            deleteRunnerVolumeService: service
        )

        await #expect(throws: TestError.forbidden) {
            try await subject.run(
                volumeID: RunnerVolumeTestData.id,
                account: nil,
                path: "/project",
                json: false
            )
        }
        #expect(!ui().contains("Success"))
    }

    @Test(.withMockedEnvironment(), .withMockedNoora, arguments: [false, true])
    func forwardsResolvedContextAndRendersResponse(json: Bool) async throws {
        let service = MockDeleteRunnerVolumeServicing()
        let response: RunnerVolumeDeleteResult = try RunnerVolumeTestData
            .decode("{\"id\":\"\(RunnerVolumeTestData.id)\",\"deleted\":true}")
        given(service).deleteRunnerVolume(
            accountHandle: .value("resolved-account"),
            serverURL: .value(RunnerVolumeTestData.serverURL),
            volumeID: .value(RunnerVolumeTestData.id)
        ).willReturn(response)
        let subject = RunnerVolumeDeleteCommandService(
            configLoader: try await RunnerVolumeTestData.configLoader(),
            serverEnvironmentService: RunnerVolumeTestData.serverEnvironmentService(),
            deleteRunnerVolumeService: service
        )

        try await subject.run(volumeID: RunnerVolumeTestData.id, account: nil, path: "/project", json: json)

        verify(service).deleteRunnerVolume(
            accountHandle: .value("resolved-account"),
            serverURL: .value(RunnerVolumeTestData.serverURL),
            volumeID: .value(RunnerVolumeTestData.id)
        ).called(1)
        #expect(ui().contains(json ? "deleted" : "Volume \(RunnerVolumeTestData.id) deleted."))
    }
}
