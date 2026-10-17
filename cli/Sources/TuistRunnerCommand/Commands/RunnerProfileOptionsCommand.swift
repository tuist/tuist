import ArgumentParser
import Foundation
import TuistNooraExtension

public struct RunnerProfileOptionsCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "options",
        abstract: "List the machine shapes and Xcode versions runner profiles can use."
    )

    @OptionGroup var options: RunnerProfileOptions

    public var jsonThroughNoora: Bool { true }

    public func run() async throws {
        try await RunnerProfileOptionsCommandService().run(account: options.account, path: options.path, json: options.json)
    }
}
