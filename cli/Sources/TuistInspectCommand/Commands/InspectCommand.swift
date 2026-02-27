import ArgumentParser

public struct InspectCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        var subcommands: [ParsableCommand.Type] = [
            InspectBundleCommand.self,
        ]
        #if os(macOS)
        subcommands.append(contentsOf: [
            InspectDependenciesCommand.self,
            InspectImplicitImportsCommand.self,
            InspectRedundantImportsCommand.self,
            InspectBuildCommand.self,
            InspectTestCommand.self,
        ])
        #endif
        return CommandConfiguration(
            commandName: "inspect",
            abstract: "Inspect your project to identify issues such as implicit or redundant dependencies.",
            subcommands: subcommands
        )
    }
}
