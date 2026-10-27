import Foundation
import Noora
import TuistConfigLoader
import TuistEnvironment
import TuistHTTP
import TuistServer

protocol RunnerVolumeShowCommandServicing {
    func run(volumeID: String, account: String?, path: String?, json: Bool) async throws
}

struct RunnerVolumeShowCommandService: RunnerVolumeShowCommandServicing {
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let fullHandleService: FullHandleServicing
    private let getRunnerVolumeService: GetRunnerVolumeServicing

    init(
        configLoader: ConfigLoading = ConfigLoader(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        fullHandleService: FullHandleServicing = FullHandleService(),
        getRunnerVolumeService: GetRunnerVolumeServicing = GetRunnerVolumeService()
    ) {
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
        self.fullHandleService = fullHandleService
        self.getRunnerVolumeService = getRunnerVolumeService
    }

    func run(volumeID: String, account: String?, path: String?, json: Bool) async throws {
        let (accountHandle, serverURL) = try await RunnerAccount.resolve(
            account: account,
            path: path,
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService,
            fullHandleService: fullHandleService
        )
        let response = try await getRunnerVolumeService.getRunnerVolume(
            accountHandle: accountHandle,
            serverURL: serverURL,
            volumeID: volumeID
        )
        if json {
            try Noora.current.json(response)
        } else {
            Noora.current.passthrough("\(RunnerVolumeOutput.details(response))")
        }
    }
}
