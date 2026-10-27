import ArgumentParser
import Foundation
import TuistEnvKey

public struct OrganizationBillingCommand: AsyncParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "billing",
            _superCommandName: "organization",
            abstract: "Open billing dashboard for the specified organization."
        )
    }

    @Argument(
        help: "The name of the organization to show billing dashboard for.",
        envKey: .organizationBillingOrganizationName
    )
    var organizationName: String

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .organizationBillingPath
    )
    var path: String?

    public func run() async throws {
        try await OrganizationBillingService().run(
            organizationName: organizationName,
            directory: path
        )
    }
}
