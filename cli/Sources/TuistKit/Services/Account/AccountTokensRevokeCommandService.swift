import Foundation
import Path
import TuistLoader
import TuistServer
import TuistSupport

protocol AccountTokensRevokeCommandServicing {
    func run(
        accountHandle: String,
        tokenName: String,
        directory: String?
    ) async throws
}

final class AccountTokensRevokeCommandService: AccountTokensRevokeCommandServicing {
    private let revokeAccountTokenService: RevokeAccountTokenServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        revokeAccountTokenService: RevokeAccountTokenServicing = RevokeAccountTokenService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.revokeAccountTokenService = revokeAccountTokenService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        accountHandle: String,
        tokenName: String,
        directory: String?
    ) async throws {
        let path = try await Environment.current.pathRelativeToWorkingDirectory(directory)
        let config = try await configLoader.loadConfig(path: path)
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        try await revokeAccountTokenService.revokeAccountToken(
            accountHandle: accountHandle,
            tokenName: tokenName,
            serverURL: serverURL
        )

        Logger.current.info("The account token '\(tokenName)' was successfully revoked.")
    }
}
