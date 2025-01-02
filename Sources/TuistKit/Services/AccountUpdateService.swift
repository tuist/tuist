import FileSystem
import Foundation
import Path
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport

protocol AccountUpdateServicing: AnyObject {
    func run(
        accountHandle: String?,
        handle: String?,
        directory: String?
    ) async throws
}

enum AccountUpdateError: Error {
    case missingAccountHandle
}

final class AccountUpdateService: AccountUpdateServicing {
    private let configLoader: ConfigLoading
    private let fileSystem: FileSysteming
    private let serverURLService: ServerURLServicing
    private let updateAccountService: UpdateAccountServicing
    private let serverSessionController: ServerSessionControlling

    // MARK: - Init

    init(
        configLoader: ConfigLoading = ConfigLoader(warningController: WarningController.shared),
        fileSystem: FileSysteming = FileSystem(),
        serverURLService: ServerURLServicing = ServerURLService(),
        updateAccountService: UpdateAccountServicing = UpdateAccountService(),
        serverSessionController: ServerSessionControlling = ServerSessionController()
    ) {
        self.configLoader = configLoader
        self.fileSystem = fileSystem
        self.serverURLService = serverURLService
        self.updateAccountService = updateAccountService
        self.serverSessionController = serverSessionController
    }

    func run(
        accountHandle: String?,
        handle: String?,
        directory: String?
    ) async throws {
        let directoryPath: AbsolutePath
        if let directory {
            directoryPath = try AbsolutePath(
                validating: directory, relativeTo: try await fileSystem.currentWorkingDirectory()
            )
        } else {
            directoryPath = try await fileSystem.currentWorkingDirectory()
        }

        let config = try await configLoader.loadConfig(path: directoryPath)
        let serverURL = try serverURLService.url(configServerURL: config.url)

        let sendAccountHandle: String?
        if let accountHandle { sendAccountHandle = accountHandle } else { sendAccountHandle = try await serverSessionController.whoami(serverURL: serverURL) }
        if sendAccountHandle == nil { throw AccountUpdateError.missingAccountHandle}

        if let name = try await updateAccountService.updateAccount(serverURL: serverURL, accountHandle: sendAccountHandle!, handle: handle) {
            logger.notice("Successfully updated username to \(name).", metadata: .success)
        }
    }
}
