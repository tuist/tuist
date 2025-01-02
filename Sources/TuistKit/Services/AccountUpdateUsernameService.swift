import Foundation
import Path
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport

protocol AccountUpdateUsernameServicing: AnyObject {
    func run(
        name: String,
        directory: String?
    ) async throws
}

final class AccountUpdateUsernameService: AccountUpdateUsernameServicing {
    private let updateAccountUsernameService: UpdateAccountUsernameServicing
    private let serverURLService: ServerURLServicing
    private let configLoader: ConfigLoading

    // MARK: - Init

    init(
        updateAccountUsernameService: UpdateAccountUsernameServicing = UpdateAccountUsernameService(),
        serverURLService: ServerURLServicing = ServerURLService(),
        configLoader: ConfigLoading = ConfigLoader(warningController: WarningController.shared)
    ) {
        self.updateAccountUsernameService = updateAccountUsernameService
        self.serverURLService = serverURLService
        self.configLoader = configLoader
    }

    func run(
        name: String,
        directory: String?
    ) async throws {
        let directoryPath: AbsolutePath
        if let directory {
            directoryPath = try AbsolutePath(
                validating: directory, relativeTo: FileHandler.shared.currentPath)
        } else {
            directoryPath = FileHandler.shared.currentPath
        }
        let config = try await configLoader.loadConfig(path: directoryPath)
        let serverURL = try serverURLService.url(configServerURL: config.url)

        if let name = try await updateAccountUsernameService.updateAccountUsername(serverURL: serverURL, name: name) {
            logger.notice("Successfully updated username to \(name).", metadata: .success)
        }
    }
}
