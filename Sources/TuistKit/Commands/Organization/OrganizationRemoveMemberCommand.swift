import ArgumentParser
import Foundation
import Path
import TuistSupport

struct OrganizationRemoveMemberCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "member",
            _superCommandName: "remove",
            abstract: "Remove a member from your organization."
        )
    }

    @Argument(
        help: "The name of the organization to remove the organization member from.",
        envKey: .organizationRemoveMemberOrganizationName
    )
    var organizationName: String

    @Argument(
        help: "The username of the member you want to remove from the organization.",
        envKey: .organizationRemoveMemberUsername
    )
    var username: String

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .organizationRemoveMemberPath
    )
    var path: String?

    func run() async throws {
        try await OrganizationRemoveMemberService().run(
            organizationName: organizationName,
            username: username,
            directory: path
        )
    }
}
