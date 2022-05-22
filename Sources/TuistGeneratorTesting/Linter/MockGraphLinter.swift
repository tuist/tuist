import Foundation
import TuistCore
import TuistGraph
import TuistSupport
@testable import TuistGenerator

public class MockGraphLinter: GraphLinting {
    var invokedLint = false
    var invokedLintCount = 0
    var invokedLintParameters: (graphTraverser: GraphTraversing, Void)?
    var invokedLintParametersList = [(graphTraverser: GraphTraversing, Void)]()
    var stubbedLintResult: [LintingIssue]! = []

    public func lint(graphTraverser: GraphTraversing) -> [LintingIssue] {
        invokedLint = true
        invokedLintCount += 1
        invokedLintParameters = (graphTraverser, ())
        invokedLintParametersList.append((graphTraverser, ()))
        return stubbedLintResult
    }
}
