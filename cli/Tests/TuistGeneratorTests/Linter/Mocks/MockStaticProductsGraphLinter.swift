import Foundation
import TuistCore
@testable import TuistGenerator

class MockStaticProductsGraphLinter: StaticProductsGraphLinting {
    var invokedLint = false
    var invokedLintCount = 0
    var invokedLintParameters: (graphTraverser: GraphTraversing, configGeneratedProjectOptions: TuistGeneratedProjectOptions)?
    var invokedLintParametersList = [(
        graphTraverser: GraphTraversing,
        configGeneratedProjectOptions: TuistGeneratedProjectOptions
    )]()
    var stubbedLintResult: [LintingIssue]! = []

    func lint(graphTraverser: GraphTraversing, configGeneratedProjectOptions: TuistGeneratedProjectOptions) -> [LintingIssue] {
        invokedLint = true
        invokedLintCount += 1
        invokedLintParameters = (graphTraverser, configGeneratedProjectOptions)
        invokedLintParametersList.append((graphTraverser, configGeneratedProjectOptions))
        return stubbedLintResult
    }
}
