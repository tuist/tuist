import ArgumentParser
import Foundation
import Path
import TuistSupport

struct OrganizationDeleteCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "delete",
            _superCommandName: "organization",
            abstract: "Delete a new organization."
        )
    }

    @Argument(
        help: "The name of the organization to delete.",
        completion: .directory,
        envKey: .cloudOrganizationDeleteOrganizationName
    )
    var organizationName: String

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .cloudOrganizationDeletePath
    )
    var path: String?

    func run() async throws {
        try await OrganizationDeleteService().run(
            organizationName: organizationName,
            directory: path
        )
    }
}
