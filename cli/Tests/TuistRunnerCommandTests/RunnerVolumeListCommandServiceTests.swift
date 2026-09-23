import Foundation
import Mockable
import Testing
import TuistNooraTesting
import TuistServer
@testable import TuistRunnerCommand

struct RunnerVolumeListCommandServiceTests {
    @Test(.withMockedNoora, arguments: [false, true])
    func forwardsResolvedContextAndRendersResponse(json: Bool) async throws {
        let service = MockListRunnerVolumesServicing()
        let response: RunnerVolumesPage = try RunnerVolumeTestData
            .decode("{\"volumes\":[\(RunnerVolumeTestData.volume)],\"pagination_metadata\":\(RunnerVolumeTestData.pagination)}")
        given(service).listRunnerVolumes(
            accountHandle: .value("resolved-account"),
            serverURL: .value(StubRunnerVolumeContextService.serverURL),
            name: .value("gradle"),
            repository: .value("demo/android-app"),
            sortBy: .value("used_space"),
            sortOrder: .value("asc"),
            page: .value(2),
            pageSize: .value(5)
        ).willReturn(response)
        let subject = RunnerVolumeListCommandService(
            contextService: StubRunnerVolumeContextService(),
            listRunnerVolumesService: service
        )

        try await subject.run(
            account: "explicit-account",
            path: "/project",
            name: "gradle",
            repository: "demo/android-app",
            sortBy: "used_space",
            sortOrder: "asc",
            page: 2,
            pageSize: 5,
            json: json
        )

        verify(service).listRunnerVolumes(
            accountHandle: .value("resolved-account"),
            serverURL: .value(StubRunnerVolumeContextService.serverURL),
            name: .value("gradle"),
            repository: .value("demo/android-app"),
            sortBy: .value("used_space"),
            sortOrder: .value("asc"),
            page: .value(2),
            pageSize: .value(5)
        ).called(1)
        #expect(ui().contains(json ? "pagination_metadata" : "Never"))
    }
}
