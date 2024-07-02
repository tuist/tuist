import ArgumentParser
import Foundation
import Path
import TuistSupport

struct OrganizationRemoveSSOCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "sso",
            _superCommandName: "remove",
            abstract: "Remove the SSO provider for your organization."
        )
    }

    @Argument(
        help: "The name of the organization for which you want to update the SSO provider for.",
        envKey: .organizationRemoveSSOOrganizationName
    )
    var organizationName: String

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .organizationRemoveSSOPath
    )
    var path: String?

    func run() async throws {
        try await OrganizationRemoveSSOService().run(
            organizationName: organizationName,
            directory: path
        )
    }
}
