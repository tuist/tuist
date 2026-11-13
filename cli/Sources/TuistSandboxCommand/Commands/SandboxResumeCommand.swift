import ArgumentParser
import TuistNooraExtension
import TuistServer

public struct SandboxResumeCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "resume",
        abstract: "Resume a paused or archived sandbox."
    )

    @OptionGroup var sandbox: SandboxID
    @OptionGroup var options: SandboxOptions

    public var jsonThroughNoora: Bool { true }

    public func run() async throws {
        try await SandboxCommandService().transition(.resume, options: options.values, sandboxID: sandbox.sandboxID)
    }
}
