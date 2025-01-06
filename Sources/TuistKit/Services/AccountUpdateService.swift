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
    private let refreshAuthTokenService: RefreshAuthTokenServicing
    private let serverSessionController: ServerSessionControlling
    private let serverAuthenticationController: ServerAuthenticationControlling

    // MARK: - Init

    init(
        configLoader: ConfigLoading = ConfigLoader(warningController: WarningController.shared),
        fileSystem: FileSysteming = FileSystem(),
        serverURLService: ServerURLServicing = ServerURLService(),
        updateAccountService: UpdateAccountServicing = UpdateAccountService(),
        refreshAuthTokenService: RefreshAuthTokenServicing = RefreshAuthTokenService(),
        serverSessionController: ServerSessionControlling = ServerSessionController(),
        serverAuthenticationController: ServerAuthenticationControlling = ServerAuthenticationController()
    ) {
        self.configLoader = configLoader
        self.fileSystem = fileSystem
        self.serverURLService = serverURLService
        self.updateAccountService = updateAccountService
        self.refreshAuthTokenService = refreshAuthTokenService
        self.serverSessionController = serverSessionController
        self.serverAuthenticationController = serverAuthenticationController
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

        let account = try await updateAccountService.updateAccount(
            serverURL: serverURL,
            accountHandle: sendAccountHandle!,
            handle: handle
        )

        guard let token = try await serverAuthenticationController.authenticationToken(serverURL: serverURL)
        else {
            throw ServerClientAuthenticationError.notAuthenticated
        }

        switch token {
        case let .user(legacyToken: legacyToken, accessToken: accessToken, refreshToken: refreshToken):
            if let refreshToken {
                let result = try await refreshAuthTokenService.refreshTokens(
                    serverURL: serverURL,
                    refreshToken: refreshToken.token
                )
            }
        case _:
            return
        }

        ServiceContext.current?.logger?.notice("Successfully updated account.", metadata: .success)
    }
}
