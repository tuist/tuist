import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

struct CloudInitCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "init",
            _superCommandName: "cloud",
            abstract: "Creates a new tuist cloud project."
        )
    }

    @Argument(
        help: "The name of the project to create.",
        completion: .directory,
        envKey: .cloudInitName
    )
    var name: String

    @Option(
        name: .shortAndLong,
        help: "Organization to initialize the Cloud project with. If not specified, the project is created with your personal Cloud account.",
        envKey: .cloudInitOrganization
    )
    var organization: String?

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .cloudInitPath
    )
    var path: String?

    func run() async throws {
        try await CloudInitService().createProject(
            name: name,
            organization: organization,
            directory: path
        )
    }
}
