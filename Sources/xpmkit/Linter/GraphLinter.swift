import Foundation

protocol GraphLinting: AnyObject {
    func lint(graph: Graph) -> [LintingIssue]
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

    func lint(graph: Graph) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        issues.append(contentsOf: ensurePlatformsAreCompatible(graph: graph))
        issues.append(contentsOf: graph.projects.flatMap(projectLinter.lint))
        return issues
    }

    fileprivate func ensurePlatformsAreCompatible(graph _: Graph) -> [LintingIssue] {
        return []
    }

    // TODO: Validate invalid platforms.
    // TODO: Validate invalid dependencies test -> test
}
