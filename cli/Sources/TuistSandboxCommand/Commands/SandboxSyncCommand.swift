import ArgumentParser
import TuistNooraExtension

public struct SandboxSyncCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Mirror the local Git worktree's files into a sandbox, including uncommitted and untracked ones.",
        discussion: """
        One way, file by file: the sandbox's copy ends up with exactly the worktree's files that Git does not ignore, \
        and files there that the worktree has are overwritten. Files the sandbox created that Git ignores, such as \
        build products, stay, so builds there stay incremental. The sandbox needs neither Git nor access to the \
        repository. The first sync uploads every file; later ones upload only files changed since the last sync. \
        Pass --path to sync another directory's repository.
        """
    )

    @OptionGroup var sandbox: SandboxID
    @OptionGroup var options: SandboxOptions

    @Option(name: .long, help: "The repository's path in the sandbox. Defaults to $HOME/work/<repository name>.")
    var to: String?

    public var jsonThroughNoora: Bool { true }

    public func run() async throws {
        try await SandboxCommandService().sync(options: options.values, sandboxID: sandbox.sandboxID, destination: to)
    }
}
