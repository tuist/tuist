import ArgumentParser
import Foundation
import Path
import TuistSupport

struct OrganizationCreateCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "create",
            _superCommandName: "organization",
            abstract: "Create a new organization."
        )
    }

    @Argument(
        help: "The name of the organization to create.",
        envKey: .organizationCreateOrganizationName
    )
    var organizationName: String

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .organizationCreatePath
    )
    var path: String?

    func run() async throws {
        try await OrganizationCreateService().run(
            organizationName: organizationName,
            directory: path
        )
    }
}
