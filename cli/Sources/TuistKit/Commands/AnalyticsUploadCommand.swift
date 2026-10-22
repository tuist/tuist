import ArgumentParser
import TuistSupport

public struct AnalyticsUploadCommand: AsyncParsableCommand, ProjectPathProviding {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "analytics-upload",
        abstract: "Upload a command event to the server",
        shouldDisplay: false
    )

    @Argument(
        help: "Path to the JSON file containing the command event."
    )
    var eventFilePath: String?

    @Argument(
        help: "The full handle of the project (account-handle/project-handle)."
    )
    var fullHandle: String?

    @Argument(
        help: "The server URL."
    )
    var serverURL: String?

    @Argument(
        help: "Path to the session directory containing logs and network recordings."
    )
    var sessionDirectory: String?

    @Option(name: .long, help: .hidden)
    var projectPath: String?

    @Flag(name: .long, help: .hidden)
    var flushReportOutbox = false

    public var path: String? { projectPath }

    public func validate() throws {
        if flushReportOutbox, eventFilePath == nil { return }
        guard eventFilePath != nil, fullHandle != nil, serverURL != nil else {
            throw ValidationError("Pass the command event file, the project's full handle and the server URL.")
        }
    }

    public func run() async throws {
        guard let eventFilePath, let fullHandle, let serverURL else {
            await AnalyticsUploadCommandService().flushReportOutbox()
            return
        }
        try await AnalyticsUploadCommandService().run(
            eventFilePath: eventFilePath,
            fullHandle: fullHandle,
            serverURL: serverURL,
            sessionDirectory: sessionDirectory,
            projectPath: projectPath
        )
    }
}
