import ArgumentParser
import Foundation
import TuistNooraExtension

public struct SandboxExecCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "exec",
        abstract: "Run a shell command in a sandbox, resuming it first when paused, and stream its output.",
        discussion: """
        The command runs with `bash -l` in the sandbox. It starts detached, so it outlives dropped connections: the \
        output stream reconnects where it stopped, however long the command runs. On a macOS sandbox whose host CI is \
        using, it waits for the host for up to 15 minutes. Interrupting cancels the command. Exits with the command's \
        status, 124 when it times out and 130 when it is cancelled. With --json, prints the whole output as one \
        object once the command ends.

        With --wait, it returns after that many seconds while the command keeps running, prints on stderr how to \
        continue it (with --json: status `running`, `command_id` and the offsets), and exits with 75. Continuing with \
        --attach streams the output from those offsets and ends like the original would have, so a long build fits \
        into tool calls that have a time limit.
        """
    )

    @OptionGroup var sandbox: SandboxID
    @OptionGroup var options: SandboxOptions

    @Option(name: .long, help: "Working directory in the sandbox. Defaults to the sandbox's workspace.")
    var cwd: String?

    @Option(name: .long, parsing: .singleValue, help: "An environment variable as NAME=VALUE. Repeatable. Never stored.")
    var env: [String] = []

    @Option(name: .long, help: "Kill the command after this many seconds (1–21600). Defaults to one hour.")
    var timeout: Int?

    @Option(
        name: .long,
        help: "Return after this many seconds (1–21600) if the command is still running, leaving it running, and exit with 75."
    )
    var wait: Int?

    @Option(name: .long, help: "Continue a command started earlier, by its ID, instead of starting one.")
    var attach: String?

    @Option(name: .long, help: "With --attach, the stdout bytes already received. Defaults to 0, the whole output.")
    var stdoutOffset: Int?

    @Option(name: .long, help: "With --attach, the stderr bytes already received. Defaults to 0, the whole output.")
    var stderrOffset: Int?

    @Argument(parsing: .postTerminator, help: "The command to run, after `--`.")
    var command: [String] = []

    public var jsonThroughNoora: Bool { true }

    var environment: [String: String] {
        Dictionary(env.map { entry in
            let parts = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return (String(parts[0]), parts.count > 1 ? String(parts[1]) : "")
        }, uniquingKeysWith: { $1 })
    }

    public func validate() throws {
        if let attach {
            guard UUID(uuidString: attach) != nil else { throw ValidationError("--attach takes a command UUID.") }
            guard command.isEmpty, cwd == nil, env.isEmpty, timeout == nil else {
                throw ValidationError("--attach continues a command, so it takes no command, --cwd, --env or --timeout.")
            }
        } else {
            guard !command.isEmpty else { throw ValidationError("Pass the command to run after `--`.") }
            guard stdoutOffset == nil, stderrOffset == nil else {
                throw ValidationError("--stdout-offset and --stderr-offset go with --attach.")
            }
        }
        if [stdoutOffset, stderrOffset].contains(where: { ($0 ?? 0) < 0 }) {
            throw ValidationError("Offsets can't be negative.")
        }
        if let timeout, !(1 ... 21600).contains(timeout) { throw ValidationError("Timeout must be 1–21600 seconds.") }
        if let wait, !(1 ... 21600).contains(wait) { throw ValidationError("Wait must be 1–21600 seconds.") }
        if let invalid = env.first(where: { !$0.contains("=") || $0.hasPrefix("=") }) {
            throw ValidationError("Pass environment variables as NAME=VALUE, not \(invalid).")
        }
    }

    public func run() async throws {
        try await SandboxCommandService().exec(
            options: options.values,
            sandboxID: sandbox.sandboxID,
            command: command.joined(separator: " "),
            cwd: cwd,
            environment: environment,
            timeoutMs: timeout.map { $0 * 1000 },
            waitSeconds: wait,
            attach: attach?.lowercased(),
            offsets: SandboxRemote.Offsets(stdout: stdoutOffset ?? 0, stderr: stderrOffset ?? 0)
        )
    }
}
