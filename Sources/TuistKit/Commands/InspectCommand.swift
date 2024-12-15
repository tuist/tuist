import ArgumentParser

struct InspectCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "inspect",
            abstract: "Find implicit or redudant dependencies",
            subcommands: [
                InspectImplicitImportsCommand.self,
                InspectRedundantImportsCommand.self,
            ]
        )
    }
}
