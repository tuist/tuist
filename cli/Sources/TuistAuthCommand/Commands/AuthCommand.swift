import ArgumentParser
import Foundation

public struct AuthCommand: ParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "auth",
            abstract: "Manage authentication",
            subcommands: [
                LoginCommand.self,
                LogoutCommand.self,
                WhoamiCommand.self,
                RefreshTokenCommand.self,
            ]
        )
    }
}
