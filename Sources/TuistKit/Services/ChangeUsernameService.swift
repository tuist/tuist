import Foundation
import Path
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport

protocol ChangeUsernameServicing: AnyObject {
    func run(
        name: String,
        directory: String?
    ) async throws
}

final class ChangeUsernameService: ChangeUsernameServicing {
    private let updateUsernameService: UpdateUsernameServicing
    private let serverURLService: ServerURLServicing
    private let configLoader: ConfigLoading

    // MARK: - Init

    init(
        updateUsernameService: UpdateUsernameServicing = UpdateUsernameService(),
        serverURLService: ServerURLServicing = ServerURLService(),
        configLoader: ConfigLoading = ConfigLoader(warningController: WarningController.shared)
    ) {
        self.updateUsernameService = updateUsernameService
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

        if let name = try await updateUsernameService.updateUsername(serverURL: serverURL, name: name) {
            logger.notice("Successfully updated username to \(name).", metadata: .success)
        }
    }
}
