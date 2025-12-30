import ArgumentParser

struct AccountCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "account",
            abstract: "A set of commands to manage your Tuist account",
            subcommands: [
                AccountTokensCommand.self,
                AccountUpdateCommand.self,
            ]
        )
    }
}
