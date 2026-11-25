import ArgumentParser
import Foundation
import TuistNooraExtension
import TuistServer

public struct SandboxCreateCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Boot a bare sandbox from a template. Useful to try a template before connecting an environment."
    )

    enum Platform: String, ExpressibleByArgument, CaseIterable {
        case linux, macos

        var server: ServerSandboxPlatform {
            switch self {
            case .linux: .linux
            case .macos: .darwin
            }
        }

        /// The vCPUs each offered memory size in GB comes with.
        var shapes: [Int: Int] {
            switch self {
            case .linux: [4: 2, 8: 4, 16: 8]
            case .macos: [8: 8, 16: 8, 24: 8]
            }
        }
    }

    @OptionGroup var options: SandboxOptions

    @Option(name: .long, help: "linux or macos. Defaults to linux, or macos with --xcode.")
    var platform: Platform?

    @Option(
        name: .long,
        help: """
        macOS: the exact Xcode version to boot, such as 26.1.1, from those the server's macOS sandboxes serve. \
        Implies --platform macos. Defaults to the server's default Xcode. A sandbox keeps its Xcode.
        """
    )
    var xcode: String?

    @Option(name: .long, help: "Template name. Defaults to the server's default template for the platform.")
    var template: String?

    @Option(name: .long, help: "vCPUs: 2, 4 or 8 on Linux, 8 on macOS. Pass it with --memory-gb.")
    var vcpus: Int?

    @Option(
        name: .customLong("memory-gb"),
        help: "Memory in GB: 4, 8 or 16 on Linux (with 2, 4 or 8 vCPUs), 8, 16 or 24 on macOS. Pass it with --vcpus."
    )
    var memoryGB: Int?

    @Option(name: .long, help: "Workspace disk size in GB (1–100).")
    var workspaceGb: Int?

    /// The guarantees the server offers, in vCPUs.
    static let guarantees: [Double] = [1, 2, 4, 8]

    @Option(
        name: .customLong("guaranteed-vcpus"),
        help: """
        Linux: the vCPUs the sandbox is guaranteed while it runs, whatever the rest of its node does: 1, 2, 4 or 8. \
        Without it, a quarter vCPU per GB of memory; with it, the larger of the two. The sandbox bursts into idle cores \
        past its guarantee, and is billed for at least it. A sandbox keeps its guarantee.
        """
    )
    var guaranteedVCPUs: Double?

    @Option(
        name: .customLong("lifetime-minutes"),
        help: """
        How long the sandbox may run, from creation and again after each resume: 5 to 1440 minutes, 120 by default. \
        Then its running commands are cancelled and it is paused and archived, keeping its files. \
        Extend it with `tuist sandbox extend`.
        """
    )
    var lifetimeMinutes: Int?

    @Option(
        name: .customLong("wait-timeout"),
        help: """
        How long to wait for a host when every one is busy, such as 5m or 90s, up to 60m. Without it, the create fails \
        with fleet_busy after the server's 25-second wait. With it, it tries again every 30 seconds or so until then, \
        and fails with fleet_busy when no host freed up.
        """
    )
    var waitTimeout: String?

    /// `--wait-timeout` in seconds: a whole number followed by `s`, `m` or `h`, or by nothing for seconds.
    var waitTimeoutSeconds: TimeInterval? {
        get throws {
            guard let waitTimeout else { return nil }
            let units: [Character: Int] = ["s": 1, "m": 60, "h": 3600]
            let text = waitTimeout.trimmingCharacters(in: .whitespaces).lowercased()
            let unit = text.last.flatMap { units[$0] }
            guard let count = Int(unit == nil ? text : String(text.dropLast())), (1 ... 3600).contains(count),
                  case let seconds = count * (unit ?? 1), seconds <= 3600
            else {
                throw ValidationError("--wait-timeout must be a duration from 1s to 60m, such as 5m or 90s.")
            }
            return TimeInterval(seconds)
        }
    }

    public var jsonThroughNoora: Bool { true }

    /// The platform the sandbox boots: --platform, else macOS when an Xcode is named, else Linux.
    var resolvedPlatform: Platform {
        platform ?? (xcode == nil ? .linux : .macos)
    }

    public func validate() throws {
        if xcode != nil, platform == .linux {
            throw ValidationError("--xcode picks a macOS sandbox's Xcode; drop --platform linux.")
        }
        let platform = resolvedPlatform
        switch (vcpus, memoryGB) {
        case (nil, nil): break
        case let (vcpus?, memory?) where platform.shapes[memory] == vcpus: break
        default:
            let offered = platform.shapes.sorted { $0.key < $1.key }.map { "\($0.value) vCPUs with \($0.key) GB" }
            throw ValidationError(
                "Pass --vcpus and --memory-gb together as one of \(offered.joined(separator: ", ")) for \(platform.rawValue)."
            )
        }
        if let workspaceGb, !(1 ... 100).contains(workspaceGb) {
            throw ValidationError("Workspace size must be 1–100 GB.")
        }
        try SandboxExtendCommand.validate(lifetimeMinutes: lifetimeMinutes)
        _ = try waitTimeoutSeconds
        if let guaranteedVCPUs {
            if platform != .linux {
                throw ValidationError("--guaranteed-vcpus is for Linux sandboxes; a macOS sandbox holds every vCPU.")
            }
            if !Self.guarantees.contains(guaranteedVCPUs) {
                throw ValidationError("--guaranteed-vcpus must be one of 1, 2, 4 or 8.")
            }
        }
    }

    public func run() async throws {
        try await SandboxCommandService().create(
            options: options.values,
            platform: resolvedPlatform.server,
            template: template,
            xcodeVersion: xcode,
            vcpus: vcpus,
            memoryGB: memoryGB,
            workspaceGB: workspaceGb,
            guaranteedVCPUs: guaranteedVCPUs,
            lifetimeMinutes: lifetimeMinutes,
            waitTimeout: try waitTimeoutSeconds
        )
    }
}
