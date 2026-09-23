import Foundation
import TuistConfigLoader
import TuistEnvironment
import TuistServer

struct RunnerVolumeContext {
    let accountHandle: String
    let serverURL: URL
}

protocol RunnerVolumeContextServicing {
    func resolve(account: String?, path: String?) async throws -> RunnerVolumeContext
}

enum RunnerVolumeContextServiceError: LocalizedError, Equatable {
    case missingAccount

    var errorDescription: String? {
        "Pass --account or configure a project full handle."
    }
}

struct RunnerVolumeContextService: RunnerVolumeContextServicing {
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing

    init(
        configLoader: ConfigLoading = ConfigLoader(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService()
    ) {
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
    }

    func resolve(account: String?, path: String?) async throws -> RunnerVolumeContext {
        let directory = try await Environment.current.pathRelativeToWorkingDirectory(path)
        let config = try await configLoader.loadConfig(path: directory)
        guard let account = account ?? config.fullHandle?.split(separator: "/").first.map(String.init), !account.isEmpty else {
            throw RunnerVolumeContextServiceError.missingAccount
        }
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)
        return RunnerVolumeContext(accountHandle: account, serverURL: serverURL)
    }
}
