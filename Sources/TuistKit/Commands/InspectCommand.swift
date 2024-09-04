import ArgumentParser

struct InspectCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "inspect",
            subcommands: [
                InspectImplicitImportsCommand.self,
                InspectRedundantImportsCommand.self,
            ]
        )
    }
}
