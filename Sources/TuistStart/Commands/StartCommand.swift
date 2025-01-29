import ArgumentParser
import Foundation

public struct StartCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "start",
            abstract: "Get started with Tuist in your Xcode project or create a new one.",
            shouldDisplay: false
        )
    }

    public func run() async throws {
        print("Starting")
    }
}
