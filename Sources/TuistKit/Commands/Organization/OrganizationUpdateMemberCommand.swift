import ArgumentParser
import Foundation
import Path
import TuistSupport

struct OrganizationUpdateMemberCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "member",
            _superCommandName: "update",
            abstract: "Update a member from your organization."
        )
    }

    @Argument(
        help: "The name of the organization for which you want to update the member for.",
        envKey: .organizationUpdateMemberOrganizationName
    )
    var organizationName: String

    @Argument(
        help: "The username of the member you want to update.",
        envKey: .organizationUpdateMemberUsername
    )
    var username: String

    @Option(
        help: "The new member role",
        completion: .list(["admin", "user"]),
        envKey: .organizationUpdateMemberRole
    )
    var role: String

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .organizationUpdateMemberPath
    )
    var path: String?

    func run() async throws {
        try await OrganizationUpdateMemberService().run(
            organizationName: organizationName,
            username: username,
            role: role,
            directory: path
        )
    }
}
