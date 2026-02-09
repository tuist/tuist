import ArgumentParser

public struct InspectCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "inspect",
            abstract: "Inspect your project to identify issues such as implicit or redundant dependencies.",
            subcommands: [
                InspectDependenciesCommand.self,
                InspectImplicitImportsCommand.self,
                InspectRedundantImportsCommand.self,
                InspectBuildCommand.self,
                InspectBundleCommand.self,
                InspectTestCommand.self,
            ]
        )
    }
}
