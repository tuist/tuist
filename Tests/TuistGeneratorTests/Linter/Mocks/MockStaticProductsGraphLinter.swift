import Foundation
import TuistCore
import TuistGraph
@testable import TuistGenerator

class MockStaticProductsGraphLinter: StaticProductsGraphLinting {
    var invokedLint = false
    var invokedLintCount = 0
    var invokedLintParameters: (graphTraverser: GraphTraversing, config: Config)?
    var invokedLintParametersList = [(graphTraverser: GraphTraversing, config: Config)]()
    var stubbedLintResult: [LintingIssue]! = []

    func lint(graphTraverser: GraphTraversing, config: Config) -> [LintingIssue] {
        invokedLint = true
        invokedLintCount += 1
        invokedLintParameters = (graphTraverser, config)
        invokedLintParametersList.append((graphTraverser, config))
        return stubbedLintResult
    }
}
