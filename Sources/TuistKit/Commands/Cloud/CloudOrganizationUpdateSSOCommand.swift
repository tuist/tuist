import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

enum SSOProvider: String, ExpressibleByArgument, CaseIterable {
    case google
}

struct CloudOrganizationUpdateSSOCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "sso",
            _superCommandName: "update",
            abstract: "Update the SSO provider for your organization."
        )
    }

    @Argument(
        help: "The name of the organization for which you want to update the SSO provider for.",
        envKey: .cloudOrganizationUpdateSSOOrganizationName
    )
    var organizationName: String

    @Option(
        help: "The SSO provider to use.",
        envKey: .cloudOrganizationUpdateSSOProvider
    )
    var provider: SSOProvider

    @Option(
        name: .shortAndLong,
        help: "Organization ID for your SSO provider. For Google, this is your Google domain (for example, if your email is tuist@tuist.io, the domain would be tuist.io)",
        envKey: .cloudOrganizationUpdateSSOOrganizationId
    )
    var organizationId: String

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .cloudOrganizationUpdateSSOPath
    )
    var path: String?

    func run() async throws {
        try await CloudOrganizationUpdateSSOService().run(
            organizationName: organizationName,
            provider: provider,
            organizationId: organizationId,
            directory: path
        )
    }
}
