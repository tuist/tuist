import ArgumentParser
import Foundation
import TSCBasic

/// A coomand to fetch project's dependencies.
struct DependenciesFetchCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "fetch",
                             abstract: "Fetches project's dependecies ")
    }
}
