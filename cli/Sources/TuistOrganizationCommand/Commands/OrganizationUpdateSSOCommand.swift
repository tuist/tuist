import ArgumentParser
import Foundation
import TuistEnvKey

public enum SSOProvider: String, ExpressibleByArgument, CaseIterable {
    case google, okta
}

public enum SSOEnrollmentPolicy: String, ExpressibleByArgument, CaseIterable {
    case automatic
    case invitationOnly = "invitation-only"
}

public struct OrganizationUpdateSSOCommand: AsyncParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
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
        help: "Organization ID for your SSO provider. For Google, this is your Google domain (for example, if your email is tuist@tuist.dev, the domain would be tuist.dev). For Okta, it's the organization domain (such as my-org.okta.com)",
        envKey: .organizationUpdateSSOOrganizationId
    )
    var organizationId: String

    @Option(
        help: "How authenticated users join the organization. When omitted, the current policy is preserved if the provider is unchanged. New configurations and provider changes default to automatic for Google and invitation-only for Okta.",
        envKey: .organizationUpdateSSOEnrollmentPolicy
    )
    var enrollmentPolicy: SSOEnrollmentPolicy?

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .organizationUpdateSSOPath
    )
    var path: String?

    public func run() async throws {
        try await OrganizationUpdateSSOService().run(
            organizationName: organizationName,
            provider: provider,
            organizationId: organizationId,
            enrollmentPolicy: enrollmentPolicy,
            directory: path
        )
    }
}
