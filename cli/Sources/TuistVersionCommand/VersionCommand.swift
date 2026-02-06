import ArgumentParser
import Foundation
import TuistNooraExtension

public struct VersionCommand: ParsableCommand, NooraReadyCommand {
    public var jsonThroughNoora: Bool { false }

    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "version",
            abstract: "Outputs the current version of tuist"
        )
    }

    public func run() throws {
        try VersionCommandService().run()
    }
}
