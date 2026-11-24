import ArgumentParser
import TuistNooraExtension
import TuistServer

public struct SandboxExtendCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "extend",
        abstract: "Start a sandbox's lifetime again from now, so it keeps running past its expiry.",
        discussion: """
        A sandbox created with `tuist sandbox create` or the API runs until its lifetime ends, then its running \
        commands are cancelled and it is paused and archived. Extend it before a command that may outlast it. \
        Sandboxes an Amp Orb or a Claude session owns have no lifetime.
        """
    )

    @OptionGroup var sandbox: SandboxID
    @OptionGroup var options: SandboxOptions

    @Option(
        name: .customLong("lifetime-minutes"),
        help: "The new lifetime from now: 5 to 1440 minutes. Defaults to the sandbox's current lifetime."
    )
    var lifetimeMinutes: Int?

    public var jsonThroughNoora: Bool { true }

    /// The lifetimes the server accepts, which it keeps in seconds (`Tuist.Sandboxes.Sandbox`).
    static func validate(lifetimeMinutes: Int?) throws {
        if let lifetimeMinutes, !(5 ... 1440).contains(lifetimeMinutes) {
            throw ValidationError("--lifetime-minutes must be 5–1440 (24 hours).")
        }
    }

    public func validate() throws {
        try Self.validate(lifetimeMinutes: lifetimeMinutes)
    }

    public func run() async throws {
        try await SandboxCommandService().extend(
            options: options.values,
            sandboxID: sandbox.sandboxID,
            lifetimeMinutes: lifetimeMinutes
        )
    }
}
