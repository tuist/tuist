import Foundation
import TuistCore
import TuistGraph
import TuistSupport
@testable import TuistGenerator

public class MockGraphLinter: GraphLinting {
    var invokedLint = false
    var invokedLintCount = 0
    var invokedLintParameters: (graphTraverser: GraphTraversing, config: Config)?
    var invokedLintParametersList = [(graphTraverser: GraphTraversing, config: Config)]()
    var stubbedLintResult: [LintingIssue]! = []

    public func lint(graphTraverser: GraphTraversing, config: Config) -> [LintingIssue] {
        invokedLint = true
        invokedLintCount += 1
        invokedLintParameters = (graphTraverser, config)
        invokedLintParametersList.append((graphTraverser, config))
        return stubbedLintResult
    }
}
