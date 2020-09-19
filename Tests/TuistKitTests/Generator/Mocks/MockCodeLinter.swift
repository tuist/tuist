import Foundation
import TSCBasic
import TuistCore
import TuistGenerator
@testable import TuistKit

final class MockCodeLinter: CodeLinting {
    var invokedLint = false
    var invokedLintCount = 0
    var invokedLintParameters: (sources: [AbsolutePath], path: AbsolutePath)?
    var invokedLintParametersList = [(sources: [AbsolutePath], path: AbsolutePath)]()
    var stubbedLintError: Error?

    func lint(sources: [AbsolutePath], path: AbsolutePath) throws {
        invokedLint = true
        invokedLintCount += 1
        invokedLintParameters = (sources, path)
        invokedLintParametersList.append((sources, path))
        if let error = stubbedLintError {
            throw error
        }
    }
}
