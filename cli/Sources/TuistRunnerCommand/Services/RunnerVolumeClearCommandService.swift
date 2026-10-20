import Foundation
import Noora
import TuistConfigLoader
import TuistEnvironment
import TuistHTTP
import TuistServer

protocol RunnerVolumeClearCommandServicing {
    func run(volumeID: String, account: String?, path: String?, json: Bool) async throws
}

struct RunnerVolumeClearCommandService: RunnerVolumeClearCommandServicing {
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let fullHandleService: FullHandleServicing
    private let clearRunnerVolumeService: ClearRunnerVolumeServicing

    init(
        configLoader: ConfigLoading = ConfigLoader(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        fullHandleService: FullHandleServicing = FullHandleService(),
        clearRunnerVolumeService: ClearRunnerVolumeServicing = ClearRunnerVolumeService()
    ) {
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
        self.fullHandleService = fullHandleService
        self.clearRunnerVolumeService = clearRunnerVolumeService
    }

    func run(volumeID: String, account: String?, path: String?, json: Bool) async throws {
        let (accountHandle, serverURL) = try await RunnerAccount.resolve(
            account: account,
            path: path,
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService,
            fullHandleService: fullHandleService
        )
        let response = try await clearRunnerVolumeService.clearRunnerVolume(
            accountHandle: accountHandle,
            serverURL: serverURL,
            volumeID: volumeID
        )
        if json {
            try Noora.current.json(response)
        } else {
            Noora.current.success("Saved contents cleared for volume \(volumeID).")
        }
    }
}
