import ArgumentParser
import Foundation
import Path
import TuistSupport

struct OrganizationListCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            _superCommandName: "organization",
            abstract: "List your organizations."
        )
    }

    @Flag(
        help: "The output in JSON format.",
        envKey: .organizationListJson
    )
    var json: Bool = false

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .organizationListPath
    )
    var path: String?

    func run() async throws {
        try await OrganizationListService().run(
            json: json,
            directory: path
        )
    }
}
