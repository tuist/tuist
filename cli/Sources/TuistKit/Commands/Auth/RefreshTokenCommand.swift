import ArgumentParser
import Foundation

struct RefreshTokenCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "refresh-token",
            _superCommandName: "auth",
            abstract: "Refreshes the token for a particular URL",
            shouldDisplay: false
        )
    }

    @Option(
        help: "The URL of the server the token is being refreshed for.",
        envKey: .authRefreshTokenServerURL
    )
    var serverURL: String

    @Option(
        name: .shortAndLong,
        help: "The path to a lockfile that's used to determine if there's a refresh happening.",
        completion: .directory,
        envKey: .authRefreshTokenLockfilePath
    )
    var lockFilePath: String

    func run() async throws {
        try await AuthRefreshTokenService().run(serverURL: serverURL, lockFilePath: lockFilePath)
    }
}
