import ArgumentParser
import Basic
import Foundation
import TuistSupport

struct VersionCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "envversion",
                             abstract: "Outputs the current version of tuist env.")
    }
}
