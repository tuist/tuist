import ArgumentParser

public struct RunnerProfileCommand: AsyncParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "profile",
            abstract: "Inspect runner profiles and choose which branches save their cache volumes.",
            subcommands: [RunnerProfileListCommand.self, RunnerProfileUpdateCommand.self]
        )
    }
}

struct RunnerProfileOptions: ParsableArguments {
    @Option(name: .long, help: "Account handle. Defaults to the account in the project's full handle.")
    var account: String?
    @Option(name: .shortAndLong, help: "Project directory.", completion: .directory)
    var path: String?
    @Flag(help: "Return the response as JSON.")
    var json = false
}
