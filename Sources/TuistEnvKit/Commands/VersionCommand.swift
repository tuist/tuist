import Basic
import Foundation
import ArgumentParser
import TuistSupport

struct VersionCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "envversion",
                             abstract: "Outputs the current version of tuist env.")
    }
}
