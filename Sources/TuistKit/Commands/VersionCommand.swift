import ArgumentParser
import Foundation
import TSCBasic

public struct VersionCommand: ParsableCommand {
    // MARK: - Configuration

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "version",
            abstract: "Outputs the current version of tuist"
        )
    }

    // MARK: - Init

    public init() {}

    // MARK: - ParseableCommand

    public func run() throws {
        try VersionService().run()
    }
}
