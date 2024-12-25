import ArgumentParser
import Foundation

struct WorkflowsCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "workflows",
            abstract: "Interact with the project workflows",
            subcommands: [
//                LoginCommand.self,
//                LogoutCommand.self,
//                WhoamiCommand.self,
            ],
            defaultSubcommand: LoginCommand.self
        )
    }
}
