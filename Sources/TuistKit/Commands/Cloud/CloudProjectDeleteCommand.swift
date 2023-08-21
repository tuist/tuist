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
        help: "The organization that the project belongs to. By default, this is your personal Cloud account."
    )
    var organization: String?

    @Option(
        name: .long,
        help: "URL to the cloud server."
    )
    var serverURL: String?

    func run() async throws {
        try await CloudProjectDeleteService().run(
            projectName: project,
            organizationName: organization,
            serverURL: serverURL
        )
    }
}
