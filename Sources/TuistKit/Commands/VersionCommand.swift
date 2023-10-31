import ArgumentParser
import Foundation
import TSCBasic

public struct VersionCommand: ParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "version",
            abstract: "Outputs the current version of tuist"
        )
    }

    public func run() throws {
        try VersionService().run()
    }
}
