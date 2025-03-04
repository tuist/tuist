import Foundation
import TuistCore
import TuistSupport
@testable import TuistGenerator

public class MockGraphLinter: GraphLinting {
    var invokedLint = false
    var invokedLintCount = 0
    var invokedLintParameters: (graphTraverser: GraphTraversing, config: Tuist)?
    var invokedLintParametersList = [(graphTraverser: GraphTraversing, config: Tuist)]()
    var stubbedLintResult: [LintingIssue]! = []

    public func lint(graphTraverser: GraphTraversing, config: Tuist) async throws -> [LintingIssue] {
        invokedLint = true
        invokedLintCount += 1
        invokedLintParameters = (graphTraverser, config)
        invokedLintParametersList.append((graphTraverser, config))
        return stubbedLintResult
    }
}
