import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

struct CloudOrganizationRemoveSSOCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "sso",
            _superCommandName: "remove",
            abstract: "Remove the SSO provider for your organization."
        )
    }

    @Argument(
        help: "The name of the organization for which you want to update the SSO provider for.",
        envKey: .cloudOrganizationRemoveSSOOrganizationName
    )
    var organizationName: String

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .cloudOrganizationRemoveSSOPath
    )
    var path: String?

    func run() async throws {
        try await CloudOrganizationRemoveSSOService().run(
            organizationName: organizationName,
            directory: path
        )
    }
}
