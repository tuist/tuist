import Foundation
import TuistWorkflows
import Path
import Command

enum WorkflowsRunServiceError: Error, Equatable, CustomStringConvertible {
    case workflowNotFound(name: String, available: [String])
    
    var description: String {
        switch self {
        case let .workflowNotFound(name, available):
            if available.isEmpty {
                return "The workflow with name \(name) was not found. No workflows exist in this project."
            } else {
                return "The workflow with name \(name) was not found. The available workflows are: \(available.joined(separator: ", "))"
            }
        }
    }
}

struct WorkflowsRunService {
    let workflowsLoader = WorkflowsLoader()
    let commandRunner = CommandRunner()
    
    func run(from: AbsolutePath, workflowName: String) async throws {
        let workflows = try await workflowsLoader.load(from: from)
        guard let workflow = workflows.first(where: { $0.name == workflowName }) else {
            throw WorkflowsRunServiceError.workflowNotFound(name: workflowName, available: workflows.map(\.name))
        }
        try await commandRunner.run(
            arguments: [
                "/usr/bin/env",
                "swift", "build",
                "--package-path", workflow.packageSwiftPath.parentDirectory.pathString,
                "--product", workflow.name
            ],
            workingDirectory: workflow.packageSwiftPath.parentDirectory)
        .awaitCompletion()
        
        // TODO: Forward arguments
        // TODO: Use as a working directory the root directoy.
        try await commandRunner.run(arguments: [workflow.packageSwiftPath.parentDirectory.appending(components: [".build", "debug", workflow.name]).pathString]).pipedStream().awaitCompletion()
    }
}
