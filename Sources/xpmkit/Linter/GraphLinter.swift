import Foundation

protocol GraphLinting: AnyObject {
    func lint(graph: Graphing) -> [LintingIssue]
}

class GraphLinter: GraphLinting {

    // MARK: - Attributes

    let projectLinter: ProjectLinting

    // MARK: - Init

    init(projectLinter: ProjectLinting = ProjectLinter()) {
        self.projectLinter = projectLinter
    }

    // MARK: - GraphLinting

    func lint(graph: Graphing) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        issues.append(contentsOf: graph.projects.flatMap(projectLinter.lint))
        return issues
    }
}
