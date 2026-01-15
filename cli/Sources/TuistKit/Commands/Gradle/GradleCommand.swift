import ArgumentParser

struct GradleCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "gradle",
            abstract: "A set of commands for Gradle integration.",
            subcommands: [
                GradleCacheCommand.self,
            ]
        )
    }
}
