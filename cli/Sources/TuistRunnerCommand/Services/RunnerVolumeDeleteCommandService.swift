import Foundation
import Noora
import TuistConfigLoader
import TuistEnvironment
import TuistHTTP
import TuistServer

protocol RunnerVolumeDeleteCommandServicing {
    func run(volumeID: String, account: String?, path: String?, json: Bool) async throws
}

struct RunnerVolumeDeleteCommandService: RunnerVolumeDeleteCommandServicing {
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let fullHandleService: FullHandleServicing
    private let deleteRunnerVolumeService: DeleteRunnerVolumeServicing

    init(
        configLoader: ConfigLoading = ConfigLoader(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        fullHandleService: FullHandleServicing = FullHandleService(),
        deleteRunnerVolumeService: DeleteRunnerVolumeServicing = DeleteRunnerVolumeService()
    ) {
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
        self.fullHandleService = fullHandleService
        self.deleteRunnerVolumeService = deleteRunnerVolumeService
    }

    func run(volumeID: String, account: String?, path: String?, json: Bool) async throws {
        let (accountHandle, serverURL) = try await RunnerAccount.resolve(
            account: account,
            path: path,
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService,
            fullHandleService: fullHandleService
        )
        let response = try await deleteRunnerVolumeService.deleteRunnerVolume(
            accountHandle: accountHandle,
            serverURL: serverURL,
            volumeID: volumeID
        )
        if json {
            try Noora.current.json(response)
        } else {
            Noora.current.success("Volume \(volumeID) deleted.")
        }
    }
}
