#if canImport(TuistCloud)
    import ArgumentParser
    import Foundation
    import TSCBasic
    import TuistSupport

    struct CloudOrganizationRemoveInviteCommand: AsyncParsableCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "invite",
                _superCommandName: "remove",
                abstract: "Cancel pending invitation."
            )
        }

        @Argument(
            help: "The name of the organization to cancel the invitation for."
        )
        var organizationName: String

        @Argument(
            help: "The email of the user to cancel the invitation for."
        )
        var email: String

        @Option(
            name: .long,
            help: "URL to the cloud server."
        )
        var serverURL: String?

        func run() async throws {
            try await CloudOrganizationRemoveInviteService().run(
                organizationName: organizationName,
                email: email,
                serverURL: serverURL
            )
        }
    }
#endif
