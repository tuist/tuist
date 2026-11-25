import ArgumentParser
import TuistNooraExtension

public struct SandboxScreenshotCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "screenshot",
        abstract: "Capture a macOS sandbox's booted iOS Simulator, or its whole screen, as a PNG on this machine.",
        discussion: """
        Boot a simulator first, such as with `tuist sandbox exec <id> -- xcrun simctl boot "iPhone 18 Pro"`, install \
        and launch the app, then capture it. With several simulators booted, pass --device: otherwise simctl picks \
        one of them. With --json, prints the PNG's `path`, `width` and `height` in pixels.
        """
    )

    enum Target: String, EnumerableFlag {
        case simulator
        case screen

        static func help(for value: Self) -> ArgumentHelp? {
            switch value {
            case .simulator: "Capture the booted iOS Simulator (default)."
            case .screen: "Capture the Mac's whole screen."
            }
        }
    }

    @OptionGroup var sandbox: SandboxID
    @OptionGroup var options: SandboxOptions

    @Flag var target: Target = .simulator

    @Option(name: .long, help: "The simulator to capture, by name or UDID. Defaults to the booted one.")
    var device: String?

    @Option(name: [.customShort("o"), .long], help: "Where to write the PNG on this machine, replacing what is there.")
    var out: String

    public var jsonThroughNoora: Bool { true }

    public func validate() throws {
        if target == .screen, device != nil { throw ValidationError("--device applies to --simulator only.") }
    }

    public func run() async throws {
        try await SandboxCommandService().screenshot(
            options: options.values,
            sandboxID: sandbox.sandboxID,
            target: target,
            device: device,
            localPath: out
        )
    }
}
