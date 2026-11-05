import ArgumentParser
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

    @Option(name: .long, help: "linux or macos. Defaults to linux.")
    var platform: Platform = .linux

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

    public var jsonThroughNoora: Bool { true }

    public func validate() throws {
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
    }

    public func run() async throws {
        try await SandboxCommandService().create(
            options: options.values,
            platform: platform.server,
            template: template,
            vcpus: vcpus,
            memoryGB: memoryGB,
            workspaceGB: workspaceGb
        )
    }
}
