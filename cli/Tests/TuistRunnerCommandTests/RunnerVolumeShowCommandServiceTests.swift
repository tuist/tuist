import Foundation
import Mockable
import Testing
import TuistEnvironmentTesting
import TuistHTTP
import TuistNooraTesting
import TuistServer
@testable import TuistRunnerCommand

struct RunnerVolumeShowCommandServiceTests {
    @Test(.withMockedEnvironment(), .withMockedNoora, arguments: ["configured/project", "invalid", "configured/project/extra"])
    func explicitAccountOverridesConfiguredHandle(fullHandle: String) async throws {
        let service = MockGetRunnerVolumeServicing()
        let response: RunnerVolume = try RunnerVolumeTestData.decode(RunnerVolumeTestData.volume)
        given(service).getRunnerVolume(
            accountHandle: .value("explicit"),
            serverURL: .value(RunnerVolumeTestData.serverURL),
            volumeID: .value(RunnerVolumeTestData.id)
        ).willReturn(response)
        let subject = RunnerVolumeShowCommandService(
            configLoader: try await RunnerVolumeTestData.configLoader(fullHandle: fullHandle),
            serverEnvironmentService: RunnerVolumeTestData.serverEnvironmentService(),
            getRunnerVolumeService: service
        )

        try await subject.run(volumeID: RunnerVolumeTestData.id, account: "explicit", path: "/project", json: false)

        verify(service).getRunnerVolume(
            accountHandle: .value("explicit"),
            serverURL: .value(RunnerVolumeTestData.serverURL),
            volumeID: .value(RunnerVolumeTestData.id)
        ).called(1)
    }

    @Test(.withMockedEnvironment(), arguments: ["invalid", "configured/project/extra"])
    func usesExistingFullHandleValidation(fullHandle: String) async throws {
        let subject = RunnerVolumeShowCommandService(
            configLoader: try await RunnerVolumeTestData.configLoader(fullHandle: fullHandle)
        )

        await #expect(throws: FullHandleServiceError.invalidHandle(fullHandle)) {
            try await subject.run(volumeID: RunnerVolumeTestData.id, account: nil, path: "/project", json: false)
        }
    }

    @Test(.withMockedEnvironment())
    func rejectsMissingAccount() async throws {
        let subject = RunnerVolumeShowCommandService(
            configLoader: try await RunnerVolumeTestData.configLoader(fullHandle: nil)
        )

        await #expect(throws: RunnerVolumeShowCommandServiceError.missingAccount) {
            try await subject.run(volumeID: RunnerVolumeTestData.id, account: nil, path: "/project", json: false)
        }
    }

    @Test(.withMockedEnvironment(), .withMockedNoora, arguments: [false, true])
    func forwardsResolvedContextAndRendersResponse(json: Bool) async throws {
        let service = MockGetRunnerVolumeServicing()
        let response: RunnerVolume = try RunnerVolumeTestData.decode(RunnerVolumeTestData.volume)
        given(service).getRunnerVolume(
            accountHandle: .value("resolved-account"),
            serverURL: .value(RunnerVolumeTestData.serverURL),
            volumeID: .value(RunnerVolumeTestData.id)
        ).willReturn(response)
        let subject = RunnerVolumeShowCommandService(
            configLoader: try await RunnerVolumeTestData.configLoader(),
            serverEnvironmentService: RunnerVolumeTestData.serverEnvironmentService(),
            getRunnerVolumeService: service
        )

        try await subject.run(volumeID: RunnerVolumeTestData.id, account: nil, path: "/project", json: json)

        verify(service).getRunnerVolume(
            accountHandle: .value("resolved-account"),
            serverURL: .value(RunnerVolumeTestData.serverURL),
            volumeID: .value(RunnerVolumeTestData.id)
        ).called(1)
        #expect(ui().contains(json ? "capacity_bytes" : "Capacity: 20 GB"))
    }
}
