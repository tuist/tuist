import Foundation
import Noora
import TuistServer

protocol RunnerVolumeAnalyticsCommandServicing {
    func run(volumeID: String?, account: String?, path: String?, start: Date?, end: Date?, json: Bool) async throws
}

struct RunnerVolumeAnalyticsCommandService: RunnerVolumeAnalyticsCommandServicing {
    private let contextService: RunnerVolumeContextServicing
    private let getRunnerVolumeAnalyticsService: GetRunnerVolumeAnalyticsServicing

    init(
        contextService: RunnerVolumeContextServicing = RunnerVolumeContextService(),
        getRunnerVolumeAnalyticsService: GetRunnerVolumeAnalyticsServicing = GetRunnerVolumeAnalyticsService()
    ) {
        self.contextService = contextService
        self.getRunnerVolumeAnalyticsService = getRunnerVolumeAnalyticsService
    }

    func run(volumeID: String?, account: String?, path: String?, start: Date?, end: Date?, json: Bool) async throws {
        let context = try await contextService.resolve(account: account, path: path)
        let response = try await getRunnerVolumeAnalyticsService.getRunnerVolumeAnalytics(
            accountHandle: context.accountHandle,
            serverURL: context.serverURL,
            volumeID: volumeID,
            start: start,
            end: end
        )
        if json {
            try Noora.current.json(response)
        } else {
            Noora.current.passthrough("\(RunnerVolumeOutput.analyticsSummary(response))")
        }
    }
}
