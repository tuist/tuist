import ArgumentParser
import Foundation
import Path
import FileSystem

public struct WorkflowsLSCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "ls",
            _superCommandName: "workflows",
            abstract: "Lists the workflows that are available for running."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .workflowsLSPath
    )
    var path: String?
    
    @Flag(
        help: "The output in JSON format.",
        envKey: .workflowsLSJSON
    )
    var json: Bool = false


    public func run() async throws {
        let fileSystem = FileSystem()
        let path = if let path {
            try await AbsolutePath(validating: path, relativeTo: fileSystem.currentWorkingDirectory())
        } else {
            try await fileSystem.currentWorkingDirectory()
        }
        try await WorkflowsLSService().run(from: path, json: json)
    }
}
