import ArgumentParser
import Foundation
import TuistAuthLoginCommand

public struct AuthCommand: ParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "auth",
            abstract: "Manage authentication",
            subcommands: [
                TuistAuthLoginCommand.LoginCommand.self,
                LogoutCommand.self,
                WhoamiCommand.self,
                RefreshTokenCommand.self,
            ]
        )
    }
}
