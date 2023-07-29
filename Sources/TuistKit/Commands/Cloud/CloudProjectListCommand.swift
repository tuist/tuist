import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

struct CloudProjectListCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            _superCommandName: "project",
            abstract: "List projects you have access to."
        )
    }

    @Flag(
        help: "The output in JSON format"
    )
    var json: Bool = false

    @Option(
        name: .long,
        help: "URL to the cloud server."
    )
    var serverURL: String?

    func run() async throws {
        try await CloudProjectListService().run(
            json: json,
            serverURL: serverURL
        )
    }
}
