import Foundation
import TuistCore
import TuistSupport
@testable import TuistGenerator

public class MockGraphLinter: GraphLinting {
    var invokedLint = false
    var invokedLintCount = 0
    var invokedLintParameters: (graphTraverser: GraphTraversing, configGeneratedProjectOptions: TuistGeneratedProjectOptions)?
    var invokedLintParametersList = [(
        graphTraverser: GraphTraversing,
        configGeneratedProjectOptions: TuistGeneratedProjectOptions
    )]()
    var stubbedLintResult: [LintingIssue]! = []

    public func lint(
        graphTraverser: GraphTraversing,
        configGeneratedProjectOptions: TuistGeneratedProjectOptions
    ) async throws -> [LintingIssue] {
        invokedLint = true
        invokedLintCount += 1
        invokedLintParameters = (graphTraverser, configGeneratedProjectOptions)
        invokedLintParametersList.append((graphTraverser, configGeneratedProjectOptions))
        return stubbedLintResult
    }
}
