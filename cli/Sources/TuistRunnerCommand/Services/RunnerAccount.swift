import Foundation
import TuistConfigLoader
import TuistEnvironment
import TuistHTTP
import TuistServer

enum RunnerAccountError: LocalizedError, Equatable {
    case missingAccount

    var errorDescription: String? {
        "Pass --account or configure a project full handle."
    }
}

enum RunnerAccount {
    /// Resolves the account from `--account`, falling back to the account in the project's full handle, and the
    /// server URL from the project's configuration.
    static func resolve(
        account: String?,
        path: String?,
        configLoader: ConfigLoading,
        serverEnvironmentService: ServerEnvironmentServicing,
        fullHandleService: FullHandleServicing
    ) async throws -> (accountHandle: String, serverURL: URL) {
        let directory = try await Environment.current.pathRelativeToWorkingDirectory(path)
        let config = try await configLoader.loadConfig(path: directory)
        guard let accountHandle = try account ?? config.fullHandle.map({ try fullHandleService.parse($0).accountHandle }),
              !accountHandle.isEmpty
        else {
            throw RunnerAccountError.missingAccount
        }
        return (accountHandle, try serverEnvironmentService.url(configServerURL: config.url))
    }
}
