import ArgumentParser
import Foundation
import TuistSupport

public struct ListCommand: ContextualizedAsyncParsableCommand {
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
        help: "The output in JSON format"
    )
    var json: Bool = false

    @Option(
        name: .shortAndLong,
        help: "The path where you want to list templates from",
        completion: .directory
    )
    var path: String?

    public func run() async throws {
        try await self.run(context: try TuistContext())
    }
    
    func run(context: any Context) async throws {
        let format: ListService.OutputFormat = json ? .json : .table
        try await ListService().run(
            path: path,
            outputFormat: format
        )
    }
}
