import Foundation
import TuistWorkflows
import Path

struct WorkflowsLSService {
    let workflowsLoader = WorkflowsLoader()
    
    func run(from: AbsolutePath, json: Bool) async throws {
        let workflows = try await workflowsLoader.load(from: from)
        if json {
            try outputJSON(workflows)
        } else {
            outputText(workflows)
        }
    }
    
    fileprivate func outputJSON(_ workflows: [Workflow]) throws {
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = .prettyPrinted
        jsonEncoder.keyEncodingStrategy = .convertToSnakeCase
        let json = try jsonEncoder.encode(workflows)
        let jsonString = String(data: json, encoding: .utf8)!
        logger.notice("\(jsonString)")
    }
    
    fileprivate func outputText(_ workflows: [Workflow]) {
        for workflow in workflows {
            let workflowLine = if let description = workflow.description {
                "\(workflow.name) \t\(description)"
            } else {
                workflow.name
            }
            logger.notice("\(workflowLine)")
        }
    }
}
