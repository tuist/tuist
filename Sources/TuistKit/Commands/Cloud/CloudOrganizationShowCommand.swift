import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

struct CloudOrganizationShowCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "show",
            _superCommandName: "organization",
            abstract: "Show information about the specified organization."
        )
    }

    @Argument(
        help: "The name of the organization to show.",
        envKey: .cloudOrganizationShowOrganizationName
    )
    var organizationName: String

    @Flag(
        help: "The output in JSON format.",
        envKey: .cloudOrganizationShowJson
    )
    var json: Bool = false

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .cloudOrganizationShowPath
    )
    var path: String?

    func run() async throws {
        try await CloudOrganizationShowService().run(
            organizationName: organizationName,
            json: json,
            directory: path
        )
    }
}
