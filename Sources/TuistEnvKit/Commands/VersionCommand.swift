import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

struct VersionCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "envversion",
            abstract: "Outputs the current version of tuist env."
        )
    }

    func run() throws {
        try VersionService().run()
    }
}
