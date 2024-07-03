import ArgumentParser
import Foundation
import Path
import TuistSupport

enum SSOProvider: String, ExpressibleByArgument, CaseIterable {
    case google
}

struct OrganizationUpdateSSOCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "sso",
            _superCommandName: "update",
            abstract: "Update the SSO provider for your organization."
        )
    }

    @Argument(
        help: "The name of the organization for which you want to update the SSO provider for.",
        envKey: .organizationUpdateSSOOrganizationName
    )
    var organizationName: String

    @Option(
        help: "The SSO provider to use.",
        envKey: .organizationUpdateSSOProvider
    )
    var provider: SSOProvider

    @Option(
        name: .shortAndLong,
        help: "Organization ID for your SSO provider. For Google, this is your Google domain (for example, if your email is tuist@tuist.io, the domain would be tuist.io)",
        envKey: .organizationUpdateSSOOrganizationId
    )
    var organizationId: String

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .organizationUpdateSSOPath
    )
    var path: String?

    func run() async throws {
        try await OrganizationUpdateSSOService().run(
            organizationName: organizationName,
            provider: provider,
            organizationId: organizationId,
            directory: path
        )
    }
}
