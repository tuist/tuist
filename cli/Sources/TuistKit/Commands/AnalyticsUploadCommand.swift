import ArgumentParser

struct AnalyticsUploadCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "analytics-upload",
        abstract: "Upload a command event to the server",
        shouldDisplay: false
    )

    @Argument(
        help: "Path to the JSON file containing the command event."
    )
    var eventFilePath: String

    @Argument(
        help: "The full handle of the project (account-handle/project-handle)."
    )
    var fullHandle: String

    @Argument(
        help: "The server URL."
    )
    var serverURL: String

    func run() async throws {
        try await AnalyticsUploadCommandService().run(
            eventFilePath: eventFilePath,
            fullHandle: fullHandle,
            serverURL: serverURL
        )
    }
}
