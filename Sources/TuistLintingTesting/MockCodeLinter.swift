import Foundation
import TSCBasic
import TuistCore

@testable import TuistLinting

final class MockCodeLinter: CodeLinting {
    var invokedLint = false
    var invokedLintCount = 0
    var invokedLintParameters: (sources: [AbsolutePath], path: AbsolutePath, strict: Bool)? // swiftlint:disable:this large_tuple
    var invokedLintParametersList = [(sources: [AbsolutePath], path: AbsolutePath, strict: Bool)]()
    var stubbedLintError: Error?

    func lint(sources: [AbsolutePath], path: AbsolutePath, strict: Bool) throws {
        invokedLint = true
        invokedLintCount += 1
        invokedLintParameters = (sources, path, strict)
        invokedLintParametersList.append((sources, path, strict))
        if let error = stubbedLintError {
            throw error
        }
    }
}
