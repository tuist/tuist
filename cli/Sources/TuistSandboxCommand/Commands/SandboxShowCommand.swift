import ArgumentParser
import TuistNooraExtension

public struct SandboxShowCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static let configuration = CommandConfiguration(commandName: "show", abstract: "Show a sandbox's details.")

    @OptionGroup var sandbox: SandboxID
    @OptionGroup var options: SandboxOptions

    public var jsonThroughNoora: Bool { true }

    public func run() async throws {
        try await SandboxCommandService().show(options: options.values, sandboxID: sandbox.sandboxID)
    }
}
