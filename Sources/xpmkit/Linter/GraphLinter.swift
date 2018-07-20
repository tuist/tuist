import Foundation

protocol GraphLinting: AnyObject {
    /// Lints a projects graph.
    ///
    /// - Parameter graph: projects graph to be linted.
    /// - Returns: linting issues validating the graph.
    func lint(graph: Graphing) -> [LintingIssue]
}

/// Lints the projects graph.
class GraphLinter: GraphLinting {

    // MARK: - Attributes

    /// Project validator.
    let projectLinter: ProjectLinting

    // MARK: - Init

    /// Initializes the linter with its attributes.
    ///
    /// - Parameter projectLinter: project linter.
    init(projectLinter: ProjectLinting = ProjectLinter()) {
        self.projectLinter = projectLinter
    }

    /// Lints a projects graph.
    ///
    /// - Parameter graph: projects graph to be linted.
    /// - Returns: linting issues validating the graph.
    func lint(graph: Graphing) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        issues.append(contentsOf: graph.projects.flatMap(projectLinter.lint))
        return issues
    }
}
