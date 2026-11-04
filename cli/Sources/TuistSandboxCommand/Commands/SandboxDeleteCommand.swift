import ArgumentParser
import TuistNooraExtension

public struct SandboxDeleteCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a sandbox and its disks. This cannot be undone."
    )

    @OptionGroup var sandbox: SandboxID
    @OptionGroup var options: SandboxOptions

    @Flag(name: .long, help: "Confirm deleting the sandbox and its disks.")
    var yes = false

    public var jsonThroughNoora: Bool { true }

    public func validate() throws {
        guard yes else { throw ValidationError("Pass --yes to confirm deleting the sandbox and its disks.") }
    }

    public func run() async throws {
        try await SandboxCommandService().delete(options: options.values, sandboxID: sandbox.sandboxID)
    }
}
