import ArgumentParser
import TuistNooraExtension
import TuistServer

public struct SandboxArchiveCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "archive",
        abstract: "Move a paused sandbox's disks to object storage, freeing them on its node."
    )

    @OptionGroup var sandbox: SandboxID
    @OptionGroup var options: SandboxOptions

    public var jsonThroughNoora: Bool { true }

    public func run() async throws {
        try await SandboxCommandService().transition(.archive, options: options.values, sandboxID: sandbox.sandboxID)
    }
}
