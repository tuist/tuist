import Foundation
import Noora
import TuistConfigLoader
import TuistEnvironment
import TuistHTTP
import TuistServer

protocol RunnerVolumeAnalyticsCommandServicing {
    func run(volumeID: String?, account: String?, path: String?, start: Date?, end: Date?, json: Bool) async throws
}

struct RunnerVolumeAnalyticsCommandService: RunnerVolumeAnalyticsCommandServicing {
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let fullHandleService: FullHandleServicing
    private let getRunnerVolumeAnalyticsService: GetRunnerVolumeAnalyticsServicing

    init(
        configLoader: ConfigLoading = ConfigLoader(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        fullHandleService: FullHandleServicing = FullHandleService(),
        getRunnerVolumeAnalyticsService: GetRunnerVolumeAnalyticsServicing = GetRunnerVolumeAnalyticsService()
    ) {
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
        self.fullHandleService = fullHandleService
        self.getRunnerVolumeAnalyticsService = getRunnerVolumeAnalyticsService
    }

    func run(volumeID: String?, account: String?, path: String?, start: Date?, end: Date?, json: Bool) async throws {
        let (accountHandle, serverURL) = try await RunnerAccount.resolve(
            account: account,
            path: path,
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService,
            fullHandleService: fullHandleService
        )
        let response = try await getRunnerVolumeAnalyticsService.getRunnerVolumeAnalytics(
            accountHandle: accountHandle,
            serverURL: serverURL,
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
