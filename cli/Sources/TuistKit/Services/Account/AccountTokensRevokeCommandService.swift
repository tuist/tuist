import Foundation
import Noora
import Path
import TuistLoader
import TuistServer
import TuistSupport

struct AccountTokensRevokeCommandService {
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
        path: String?
    ) async throws {
        let path = try await Environment.current.pathRelativeToWorkingDirectory(path)
        let config = try await configLoader.loadConfig(path: path)
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        try await revokeAccountTokenService.revokeAccountToken(
            accountHandle: accountHandle,
            tokenName: tokenName,
            serverURL: serverURL
        )

        Noora.current.success("The account token '\(tokenName)' was successfully revoked.")
    }
}
