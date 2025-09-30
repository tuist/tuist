import ArgumentParser

struct InspectCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "inspect",
            abstract: "Inspect your project to identify issues such as implicit or redundant dependencies.",
            subcommands: [
                InspectImplicitImportsCommand.self,
                InspectRedundantImportsCommand.self,
                InspectBuildCommand.self,
                InspectBundleCommand.self,
                InspectTestCommand.self,
            ]
        )
    }
}
