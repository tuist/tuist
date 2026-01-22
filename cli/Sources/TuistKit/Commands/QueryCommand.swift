import ArgumentParser

struct QueryCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "query",
            abstract: "Query the project graph for information about targets and dependencies.",
            subcommands: [
                QueryDepsCommand.self,
            ]
        )
    }
}
