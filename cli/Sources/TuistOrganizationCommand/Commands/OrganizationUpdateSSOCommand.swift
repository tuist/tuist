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
        help: "The identity provider organization identifier used to scope identities. For Google, this is the Google Workspace domain (for example, tuist.dev for tuist@tuist.dev). For Okta, it is the Okta organization domain (such as my-org.okta.com). This is distinct from the verified login email domain used for discovery and enrollment, which is configured in the dashboard.",
        envKey: .organizationUpdateSSOOrganizationId
    )
    var organizationId: String

    @Option(
        help: "How authenticated users join the organization. Automatic enrollment allows users from the provider's trusted domain to join without an invitation; invitation-only requires an invitation. When omitted, the current policy is preserved if the provider is unchanged. New configurations and provider changes default to automatic for Google and invitation-only for Okta.",
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
