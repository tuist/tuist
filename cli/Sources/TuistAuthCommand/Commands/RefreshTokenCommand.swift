import ArgumentParser
import Foundation
import TuistEnvKey

public struct RefreshTokenCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "refresh-token",
            _superCommandName: "auth",
            abstract: "Refreshes the token for a particular URL",
            shouldDisplay: false
        )
    }

    @Argument(
        help: "The URL of the server the token is being refreshed for.",
        envKey: .authRefreshTokenServerURL
    )
    var serverURL: String

    public func run() async throws {
        try await AuthRefreshTokenService().run(serverURL: serverURL)
    }
}
