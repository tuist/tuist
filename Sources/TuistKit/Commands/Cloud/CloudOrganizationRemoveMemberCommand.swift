#if canImport(TuistCloud)
    import ArgumentParser
    import Foundation
    import TSCBasic
    import TuistSupport

    struct CloudOrganizationRemoveMemberCommand: AsyncParsableCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "member",
                _superCommandName: "remove",
                abstract: "Remove a member from your organization."
            )
        }

        @Argument(
            help: "The name of the organization to remove the organization member from."
        )
        var organizationName: String

        @Argument(
            help: "The username of the member you want to remove from the organization."
        )
        var username: String

        @Option(
            name: .shortAndLong,
            help: "The path to the directory or a subdirectory of the project.",
            completion: .directory
        )
        var path: String?

        func run() async throws {
            try await CloudOrganizationRemoveMemberService().run(
                organizationName: organizationName,
                username: username,
                directory: path
            )
        }
    }
#endif
