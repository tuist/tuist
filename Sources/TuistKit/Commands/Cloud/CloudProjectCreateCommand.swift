import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

struct CloudProjectCreateCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "create",
            _superCommandName: "project",
            abstract: "Create a new project."
        )
    }
    
    @Argument(
        help: "The name of the project to create.",
        completion: .directory
    )
    var name: String
    
    @Option(
        name: .long,
        help: "URL to the cloud server."
    )
    var serverURL: String?

    func run() async throws {
        try await CloudProjectCreateService().run(
            name: name,
            serverURL: serverURL
        )
    }
}
