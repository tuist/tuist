#if canImport(TuistCloud)
import ArgumentParser
import Foundation
import TSCBasic

struct CloudLogoutCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "logout",
            _superCommandName: "cloud",
            abstract: "Removes an existing Cloud session."
        )
    }

    @Option(
        name: .long,
        help: "URL to the cloud server."
    )
    var serverURL: String?

    func run() throws {
        try CloudLogoutService().logout(
            serverURL: serverURL
        )
    }
}
#endif
