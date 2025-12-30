import ArgumentParser
import Foundation

struct AuthCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
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
