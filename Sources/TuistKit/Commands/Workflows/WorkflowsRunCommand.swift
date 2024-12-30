import ArgumentParser
import Foundation
import FileSystem
import Path

public struct WorkflowsRunCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "run",
            _superCommandName: "workflows",
            abstract: "Runs a workflow with the given name. The name of the workflow is the name of the executable in the Package.swift."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .workflowsRunPath
    )
    var path: String?
    
    @Argument(
        help: "The name of the workflow to run.",
        envKey: .workflowsRunWorkflow
    )
    var workflow: String

    public func run() async throws {
        let fileSystem = FileSystem()
        let path = if let path {
            try await AbsolutePath(validating: path, relativeTo: fileSystem.currentWorkingDirectory())
        } else {
            try await fileSystem.currentWorkingDirectory()
        }
        try await WorkflowsRunService().run(from: path, workflowName: workflow)
    }
}
