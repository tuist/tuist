import Foundation
import TuistCore
@testable import TuistGenerator

final class MockEnvironmentLinter: EnvironmentLinting {
    var lintStub: [LintingIssue]?
    var lintArgs: [TuistConfig] = []

    func lint(config: TuistConfig) throws -> [LintingIssue] {
        lintArgs.append(config)
        return lintStub ?? []
    }
}
