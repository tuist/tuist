import ArgumentParser
import Foundation
import TSCBasic

/// A command to update project's dependencies.
struct DependenciesUpdateCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "update",
                             abstract: "Updates project's dependencies.")
    }
}
