import ArgumentParser
import Foundation
import Path
import TuistSupport

struct OrganizationShowCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "show",
            _superCommandName: "organization",
            abstract: "Show information about the specified organization."
        )
    }

    @Argument(
        help: "The name of the organization to show.",
        envKey: .organizationShowOrganizationName
    )
    var organizationName: String

    @Flag(
        help: "The output in JSON format.",
        envKey: .organizationShowJson
    )
    var json: Bool = false

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .organizationShowPath
    )
    var path: String?

    func run() async throws {
        try await OrganizationShowService().run(
            organizationName: organizationName,
            json: json,
            directory: path
        )
    }
}
