import ArgumentParser
import FileSystem
import Foundation
import Path
import ServiceContextModule

public struct StartCommand: AsyncParsableCommand {
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "start",
            abstract: "Get started with Tuist in your Xcode project or create a generated project.",
            shouldDisplay: true
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory from where to start.",
        completion: .directory,
        envKey: .start
    )
    var path: String?

    public init() {}

    public func run() async throws {
        try await StartService().run(from: try await directory())
    }

    private func directory() async throws -> AbsolutePath {
        let currentWorkingDirectory = try await FileSystem().currentWorkingDirectory()
        if let pathString = path {
            return try AbsolutePath(validating: pathString, relativeTo: currentWorkingDirectory)
        } else {
            return currentWorkingDirectory
        }
    }
}
