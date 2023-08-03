import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

struct CloudOrganizationListCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            _superCommandName: "organization",
            abstract: "List your organizations."
        )
    }

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
        try await CloudOrganizationListService().run(
            json: json,
            serverURL: serverURL
        )
    }
}
