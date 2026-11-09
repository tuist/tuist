import ArgumentParser
import TuistNooraExtension
import TuistServer

public struct SandboxPauseCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "pause",
        abstract: "Pause a running sandbox, snapshotting it to its node's disk."
    )

    @OptionGroup var sandbox: SandboxID
    @OptionGroup var options: SandboxOptions

    public var jsonThroughNoora: Bool { true }

    public func run() async throws {
        try await SandboxCommandService().transition(.pause, options: options.values, sandboxID: sandbox.sandboxID)
    }
}
