import ArgumentParser
import Path

struct AccountUpdateCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "update",
            _superCommandName: "account",
            abstract: "Update account settings."
        )
    }

    @Argument(
        help: "The account handle of the account to update. If omitted, defaults to the account you're currently authenticated as."
    )
    var accountHandle: String?

    @Option(
        help: "The new handle."
    )
    var handle: String

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory
    )
    var path: String?

    func run() async throws {
        try await AccountUpdateService().run(
            accountHandle: accountHandle,
            handle: handle,
            directory: path
        )
    }
}
