import ArgumentParser
import Foundation
import TuistNooraExtension

public struct RunnerProfileListCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List the account's runner profiles and the branches that save their cache volumes."
    )

    @OptionGroup var options: RunnerProfileOptions

    public var jsonThroughNoora: Bool { true }

    public func run() async throws {
        try await RunnerProfileListCommandService().run(account: options.account, path: options.path, json: options.json)
    }
}
