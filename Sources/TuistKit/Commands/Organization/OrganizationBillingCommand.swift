import ArgumentParser
import Foundation
import Path
import TuistSupport

struct OrganizationBillingCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "billing",
            _superCommandName: "organization",
            abstract: "Open billing dashboard for the specified organization."
        )
    }

    @Argument(
        help: "The name of the organization to show billing dashboard for.",
        envKey: .cloudOrganizationBillingOrganizationName
    )
    var organizationName: String

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .cloudOrganizationBillingPath
    )
    var path: String?

    func run() async throws {
        try await OrganizationBillingService().run(
            organizationName: organizationName,
            directory: path
        )
    }
}
