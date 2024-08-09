import ArgumentParser

struct LintCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "lint",
            subcommands: [LintImplicitImportsCommand.self],
            defaultSubcommand: LintImplicitImportsCommand.self
        )
    }
}
