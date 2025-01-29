import ArgumentParser
import FileSystem
import Foundation
import Path
import ServiceContextModule
import TuistStart

public struct StartCommand: AsyncParsableCommand {
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "start",
            abstract: "Get started with Tuist in your Xcode project or create a new one.",
            shouldDisplay: false
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory from where to start.",
        completion: .directory,
        envKey: .start
    )
    var path: String?

    @Option(
        name: .shortAndLong,
        help: "The Base64-encoded JSON of the start configuration.",
        envKey: .start
    )
    var configuration: String?
    private let fileSystem = FileSystem()

    public init() {}

    public func run() async throws {
        let directory = try await directory()
        let configuration = try parseOptionConfiguration() ?? promptForConfiguration(directory: directory)
        ServiceContext.current?.ui?.success("This worked")
    }

    private func directory() async throws -> AbsolutePath {
        let currentWorkingDirectory = try await fileSystem.currentWorkingDirectory()
        if let pathString = path {
            return try AbsolutePath(validating: pathString, relativeTo: currentWorkingDirectory)
        } else {
            return currentWorkingDirectory
        }
    }

    private func promptForConfiguration(directory: AbsolutePath) throws -> StartConfiguration {
        let candidates = try fileSystem.glob(directory: directory, include: ["*.xcodeproj", "*.xcworkspace"])
//        ServiceContext.current?.ui.
        return .addToExistingXcodeProjectOrWorkspace(try AbsolutePath(validating: "/"))
    }

    private func parseOptionConfiguration() throws -> StartConfiguration? {
        guard let configurationString = configuration,
              let configurationData = configurationString.data(using: .utf8),
              let decodedConfigurationData = Data(base64Encoded: configurationData) else { return nil }
        return try JSONDecoder().decode(StartConfiguration.self, from: decodedConfigurationData)
    }
}
