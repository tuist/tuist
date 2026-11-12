import ArgumentParser
import Foundation
import TuistNooraExtension

public struct SandboxCopyCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "cp",
        abstract: "Copy a file or directory into or out of a sandbox, such as a built .app, an .xcresult bundle or a screenshot.",
        discussion: """
        Write the sandbox side as <sandbox-id>:<path>. A relative path there is relative to the sandbox's workspace. \
        As with cp -r, when the destination is an existing directory, or ends with / (which creates it), the source \
        is copied into it; otherwise the source is copied to the destination path, replacing what is there.
        """
    )

    /// A path on one side of a copy.
    enum Location: Equatable {
        case local(String)
        case sandbox(id: String, path: String)

        init(_ argument: String) {
            if let colon = argument.firstIndex(of: ":"), UUID(uuidString: String(argument[..<colon])) != nil {
                self = .sandbox(id: String(argument[..<colon]), path: String(argument[argument.index(after: colon)...]))
            } else {
                self = .local(argument)
            }
        }
    }

    @OptionGroup var options: SandboxOptions

    @Argument(help: "What to copy: a local path, or <sandbox-id>:<path>.")
    var source: String

    @Argument(help: "Where to copy it: a local path, or <sandbox-id>:<path>.")
    var destination: String

    public var jsonThroughNoora: Bool { true }

    public func validate() throws {
        switch (Location(source), Location(destination)) {
        case let (.sandbox(_, path), .local), let (.local, .sandbox(_, path)):
            guard !path.isEmpty else { throw ValidationError("Pass a path after the sandbox ID, as <sandbox-id>:<path>.") }
        case (.local, .local):
            throw ValidationError("Write the sandbox side as <sandbox-id>:<path>.")
        case (.sandbox, .sandbox):
            throw ValidationError("Copy between a sandbox and this machine; one side must be a local path.")
        }
    }

    public func run() async throws {
        let service = SandboxCommandService()
        switch (Location(source), Location(destination)) {
        case let (.sandbox(id, path), .local(local)):
            try await service.download(options: options.values, sandboxID: id, remotePath: path, localPath: local)
        case let (.local(local), .sandbox(id, path)):
            try await service.upload(options: options.values, sandboxID: id, localPath: local, remotePath: path)
        default:
            preconditionFailure("validate() allows exactly one sandbox side")
        }
    }
}
