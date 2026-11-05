import ArgumentParser
import TuistNooraExtension

public struct SandboxCreateCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Boot a bare sandbox from a template. Useful to try a template before connecting an environment."
    )

    @OptionGroup var options: SandboxOptions

    @Option(name: .long, help: "Template name. Defaults to the server's default template.")
    var template: String?

    @Option(name: .long, help: "2, 4 or 8, with the matching --memory-mb (4096, 8192 or 16384).")
    var vcpus: Int?

    @Option(name: .long, help: "4096, 8192 or 16384, with the matching --vcpus.")
    var memoryMb: Int?

    @Option(name: .long, help: "Workspace disk size in GB (1–100).")
    var workspaceGb: Int?

    public var jsonThroughNoora: Bool { true }

    public func validate() throws {
        let shapes = [2: 4096, 4: 8192, 8: 16384]
        switch (vcpus, memoryMb) {
        case (nil, nil): break
        case let (vcpus?, memory?) where shapes[vcpus] == memory: break
        default: throw ValidationError("Pass --vcpus and --memory-mb together as 2/4096, 4/8192 or 8/16384.")
        }
        if let workspaceGb, !(1 ... 100).contains(workspaceGb) {
            throw ValidationError("Workspace size must be 1–100 GB.")
        }
    }

    public func run() async throws {
        try await SandboxCommandService().create(
            options: options.values,
            template: template,
            vcpus: vcpus,
            memoryMB: memoryMb,
            workspaceGB: workspaceGb
        )
    }
}
