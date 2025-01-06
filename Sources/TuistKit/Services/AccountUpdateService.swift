import FileSystem
import Foundation
import Path
import ServiceContextModule
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

enum AccountUpdateServiceError: Equatable, FatalError {
    case missingHandle

    var type: TuistSupport.ErrorType {
        switch self {
        case .missingHandle: .abort
        }
    }

    var description: String {
        switch self {
        case .missingHandle:
            return "We couldn't update the account because no handle was provided, and no logged in user was found."
        }
    }
}

final class AccountUpdateService: AccountUpdateServicing {
    private let configLoader: ConfigLoading
    private let fileSystem: FileSysteming
    private let serverURLService: ServerURLServicing
    private let updateAccountService: UpdateAccountServicing
    private let authTokenRefreshService: AuthTokenRefreshServicing
    private let serverSessionController: ServerSessionControlling

    // MARK: - Init

    init(
        configLoader: ConfigLoading = ConfigLoader(warningController: WarningController.shared),
        fileSystem: FileSysteming = FileSystem(),
        serverURLService: ServerURLServicing = ServerURLService(),
        updateAccountService: UpdateAccountServicing = UpdateAccountService(),
        authTokenRefreshService: AuthTokenRefreshServicing = AuthTokenRefreshService(),
        serverSessionController: ServerSessionControlling = ServerSessionController()
    ) {
        self.configLoader = configLoader
        self.fileSystem = fileSystem
        self.serverURLService = serverURLService
        self.updateAccountService = updateAccountService
        self.authTokenRefreshService = authTokenRefreshService
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
        if sendAccountHandle == nil { throw AccountUpdateServiceError.missingHandle }

        try await updateAccountService.updateAccount(
            serverURL: serverURL,
            accountHandle: sendAccountHandle!,
            handle: handle
        )
        try await authTokenRefreshService.run(directory: directory)

        ServiceContext.current?.logger?.notice("Successfully updated account.", metadata: .success)
    }
}
