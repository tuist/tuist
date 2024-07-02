import ArgumentParser
import Foundation
import Path
import TuistSupport

struct ProjectListCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            _superCommandName: "project",
            abstract: "List projects you have access to."
        )
    }

    @Flag(
        help: "The output in JSON format.",
        envKey: .projectListJson
    )
    var json: Bool = false

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .projectListPath
    )
    var path: String?

    func run() async throws {
        try await ProjectListService().run(
            json: json,
            directory: path
        )
    }
}
