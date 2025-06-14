import ArgumentParser
import Foundation

public struct ListCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            _superCommandName: "scaffold",
            abstract: "Lists available scaffold templates",
            subcommands: []
        )
    }

    @Flag(
        help: "The output in JSON format",
        envKey: .scaffoldListJson
    )
    var json: Bool = false

    @Option(
        name: .shortAndLong,
        help: "The path where you want to list templates from",
        completion: .directory,
        envKey: .scaffoldListPath
    )
    var path: String?

    public func run() async throws {
        let format: ListService.OutputFormat = json ? .json : .table
        try await ListService().run(
            path: path,
            outputFormat: format
        )
    }
}
