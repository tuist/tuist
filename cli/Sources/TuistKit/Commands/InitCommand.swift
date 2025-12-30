import ArgumentParser
import FileSystem
import Foundation
import Path
import TuistSupport

public struct InitCommand: AsyncParsableCommand, NooraReadyCommand {
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "init",
            abstract: "Get started with Tuist in your Xcode project or create a generated project."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory from where to start.",
        completion: .directory,
        envKey: .initPath
    )
    var path: String?

    @Option(
        name: .shortAndLong,
        help: ArgumentHelp("Base64-encoded prompt answers", visibility: .private),
        completion: nil,
        envKey: .initPath
    )
    var answers: String?

    var jsonThroughNoora: Bool = false

    public init() {}

    public func run() async throws {
        try await InitCommandService().run(
            from: try await Environment.current.pathRelativeToWorkingDirectory(path),
            answers: answers()
        )
    }

    private func answers() async throws -> InitPromptAnswers? {
        guard let answersBase64String = answers else { return nil }
        guard let answersJSONData = Data(base64Encoded: answersBase64String) else { return nil }
        return try? JSONDecoder().decode(InitPromptAnswers.self, from: answersJSONData)
    }
}
