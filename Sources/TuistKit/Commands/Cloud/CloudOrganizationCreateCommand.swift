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
        name: .long,
        help: "URL to the cloud server."
    )
    var serverURL: String?

    func run() async throws {
        try await CloudOrganizationCreateService().run(
            organizationName: organizationName,
            serverURL: serverURL
        )
    }
}
