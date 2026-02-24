import ArgumentParser
import Foundation
import TuistEnvKey

public struct OrganizationCreateCommand: AsyncParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "create",
            _superCommandName: "organization",
            abstract: "Create a new organization.",
            discussion: "By creating an organization, you agree to the Tuist Terms of Service: https://tuist.dev/terms"
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

    public func run() async throws {
        try await OrganizationCreateService().run(
            organizationName: organizationName,
            directory: path
        )
    }
}
