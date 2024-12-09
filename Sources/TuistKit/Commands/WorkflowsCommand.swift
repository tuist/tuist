import ArgumentParser

struct WorkflowsCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "workflows",
            subcommands: [WorkflowsRunCommand.self]
        )
    }
}
