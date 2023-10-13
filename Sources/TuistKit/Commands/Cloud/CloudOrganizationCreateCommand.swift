#if canImport(TuistCloud)
    import ArgumentParser
    import Foundation
    import TSCBasic
    import TuistSupport

    struct CloudOrganizationCreateCommand: AsyncParsableCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "create",
                _superCommandName: "organization",
                abstract: "Create a new organization."
            )
        }

        @Argument(
            help: "The name of the organization to create."
        )
        var organizationName: String

        @Option(
            name: .shortAndLong,
            help: "The path to the directory or a subdirectory of the project.",
            completion: .directory
        )
        var path: String?

        func run() async throws {
            try await CloudOrganizationCreateService().run(
                organizationName: organizationName,
                directory: path
            )
        }
    }
#endif
