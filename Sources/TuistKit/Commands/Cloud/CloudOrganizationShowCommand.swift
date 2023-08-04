import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

struct CloudOrganizationShowCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "show",
            _superCommandName: "organization",
            abstract: "Show information about the specified organization."
        )
    }

    @Argument(
        help: "The name of the organization to show."
    )
    var organizationName: String

    @Flag(
        help: "The output in JSON format."
    )
    var json: Bool = false

    @Option(
        name: .long,
        help: "URL to the cloud server."
    )
    var serverURL: String?

    func run() async throws {
        try await CloudOrganizationShowService().run(
            organizationName: organizationName,
            json: json,
            serverURL: serverURL
        )
    }
}
