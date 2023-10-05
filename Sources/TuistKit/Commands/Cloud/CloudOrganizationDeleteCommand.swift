#if canImport(TuistCloud)
    import ArgumentParser
    import Foundation
    import TSCBasic
    import TuistSupport

    struct CloudOrganizationDeleteCommand: AsyncParsableCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "delete",
                _superCommandName: "organization",
                abstract: "Delete a new organization."
            )
        }

        @Argument(
            help: "The name of the organization to delete.",
            completion: .directory
        )
        var organizationName: String

        @Option(
            name: .long,
            help: "URL to the cloud server."
        )
        var serverURL: String?

        func run() async throws {
            try await CloudOrganizationDeleteService().run(
                organizationName: organizationName,
                serverURL: serverURL
            )
        }
    }
#endif
