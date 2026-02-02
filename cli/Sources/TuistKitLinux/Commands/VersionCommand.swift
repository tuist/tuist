import ArgumentParser
import Foundation
import TuistConstants

struct VersionCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "version",
            abstract: "Outputs the current version of tuist"
        )
    }

    func run() throws {
        print(Constants.version)
    }
}
