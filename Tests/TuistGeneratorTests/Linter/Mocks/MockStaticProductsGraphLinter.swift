import Foundation
import TuistCore
@testable import TuistGenerator

class MockStaticProductsGraphLinter: StaticProductsGraphLinting {
    var invokedLint = false
    var invokedLintCount = 0
    var invokedLintParameters: (graphTraverser: GraphTraversing, Void)?
    var invokedLintParametersList = [(graphTraverser: GraphTraversing, Void)]()
    var stubbedLintResult: [LintingIssue]! = []

    func lint(graphTraverser: GraphTraversing) -> [LintingIssue] {
        invokedLint = true
        invokedLintCount += 1
        invokedLintParameters = (graphTraverser, ())
        invokedLintParametersList.append((graphTraverser, ()))
        return stubbedLintResult
    }
}
