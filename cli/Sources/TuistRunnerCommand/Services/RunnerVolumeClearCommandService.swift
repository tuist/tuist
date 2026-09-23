import Foundation
import Noora
import TuistConfigLoader
import TuistEnvironment
import TuistHTTP
import TuistServer

protocol RunnerVolumeClearCommandServicing {
    func run(volumeID: String, account: String?, path: String?, json: Bool) async throws
}

enum RunnerVolumeClearCommandServiceError: LocalizedError, Equatable {
    case missingAccount

    var errorDescription: String? {
        "Pass --account or configure a project full handle."
    }
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
        let directory = try await Environment.current.pathRelativeToWorkingDirectory(path)
        let config = try await configLoader.loadConfig(path: directory)
        guard let accountHandle = try account ?? config.fullHandle.map({ try fullHandleService.parse($0).accountHandle }),
              !accountHandle.isEmpty
        else {
            throw RunnerVolumeClearCommandServiceError.missingAccount
        }
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)
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
