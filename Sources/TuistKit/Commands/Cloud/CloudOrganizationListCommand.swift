import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

struct CloudOrganizationListCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            _superCommandName: "organization",
            abstract: "List your organizations."
        )
    }

    @Flag(
        help: "The output in JSON format.",
        envKey: .cloudOrganizationListJson
    )
    var json: Bool = false

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .cloudOrganizationListPath
    )
    var path: String?

    func run() async throws {
        try await CloudOrganizationListService().run(
            json: json,
            directory: path
        )
    }
}
