#if canImport(TuistCloud)
    import ArgumentParser
    import Foundation
    import TuistSupport

    struct CloudProjectDeleteCommand: AsyncParsableCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "delete",
                _superCommandName: "project",
                abstract: "Delete a Cloud project."
            )
        }

        @Argument(
            help: "The project to delete.",
            completion: .directory
        )
        var project: String

        @Option(
            name: .shortAndLong,
            help: "The organization that the project belongs to. By default, this is your personal Tuist Cloud account."
        )
        var organization: String?

        @Option(
            name: .shortAndLong,
            help: "The path to the directory or a subdirectory of the project.",
            completion: .directory
        )
        var path: String?

        func run() async throws {
            try await CloudProjectDeleteService().run(
                projectName: project,
                organizationName: organization,
                directory: path
            )
        }
    }
#endif
