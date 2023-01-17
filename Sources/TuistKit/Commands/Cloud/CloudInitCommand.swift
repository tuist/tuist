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

    @Option(
        help: "Owner of the project. Either your username or a name of the organization."
    )
    var owner: String?

    @Option(
        help: "Name of the project. The allowed characters are a-z and the dash symbol '-' (for example project-name)."
    )
    var name: String

    @Option(
        help: "URL to the cloud server. Default is tuist cloud hosted by tuist itself – https://cloud.tuist.io/"
    )
    var url: String = Constants.tuistCloudURL

    func run() async throws {
        try await CloudInitService().createProject(
            name: name,
            owner: owner,
            url: url
        )
    }
}
