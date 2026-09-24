import Foundation
import Noora
import TuistConfigLoader
import TuistEnvironment
import TuistHTTP
import TuistServer

protocol RunnerVolumeShowCommandServicing {
    func run(volumeID: String, account: String?, path: String?, json: Bool) async throws
}

enum RunnerVolumeShowCommandServiceError: LocalizedError, Equatable {
    case missingAccount

    var errorDescription: String? {
        "Pass --account or configure a project full handle."
    }
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
        let directory = try await Environment.current.pathRelativeToWorkingDirectory(path)
        let config = try await configLoader.loadConfig(path: directory)
        guard let accountHandle = try account ?? config.fullHandle.map({ try fullHandleService.parse($0).accountHandle }),
              !accountHandle.isEmpty
        else {
            throw RunnerVolumeShowCommandServiceError.missingAccount
        }
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)
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
