import Foundation
import TuistCore
@testable import TuistGenerator

class MockStaticProductsGraphLinter: StaticProductsGraphLinting {
    var invokedLint = false
    var invokedLintCount = 0
    var invokedLintParameters: (graphTraverser: GraphTraversing, config: Tuist)?
    var invokedLintParametersList = [(graphTraverser: GraphTraversing, config: Tuist)]()
    var stubbedLintResult: [LintingIssue]! = []

    func lint(graphTraverser: GraphTraversing, config: Tuist) -> [LintingIssue] {
        invokedLint = true
        invokedLintCount += 1
        invokedLintParameters = (graphTraverser, config)
        invokedLintParametersList.append((graphTraverser, config))
        return stubbedLintResult
    }
}
