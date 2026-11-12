import ArgumentParser
import TuistNooraExtension

public struct SandboxExecCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "exec",
        abstract: "Run a shell command in a sandbox, resuming it first when paused, and print its output.",
        discussion: "The command runs with `/bin/bash -lc`, and each output stream is capped at 1 MiB. Exits with the command's status."
    )

    @OptionGroup var sandbox: SandboxID
    @OptionGroup var options: SandboxOptions

    @Option(name: .long, help: "Kill the command after this many seconds (1–600). Defaults to 60.")
    var timeout: Int?

    @Argument(parsing: .postTerminator, help: "The command to run, after `--`.")
    var command: [String] = []

    public var jsonThroughNoora: Bool { true }

    public func validate() throws {
        guard !command.isEmpty else { throw ValidationError("Pass the command to run after `--`.") }
        if let timeout, !(1 ... 600).contains(timeout) { throw ValidationError("Timeout must be 1–600 seconds.") }
    }

    public func run() async throws {
        try await SandboxCommandService().exec(
            options: options.values,
            sandboxID: sandbox.sandboxID,
            command: command.joined(separator: " "),
            timeoutMs: timeout.map { $0 * 1000 }
        )
    }
}
