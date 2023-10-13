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
            name: .shortAndLong,
            help: "The path to the directory or a subdirectory of the project.",
            completion: .directory
        )
        var path: String?

        func run() async throws {
            try await CloudOrganizationDeleteService().run(
                organizationName: organizationName,
                directory: path
            )
        }
    }
#endif
