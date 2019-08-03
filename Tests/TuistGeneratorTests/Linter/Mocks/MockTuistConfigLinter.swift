import Foundation

@testable import TuistGenerator

final class MockTuistConfigLinter: TuistConfigLinting {
    var lintStub: Error?
    var lintArgs: [TuistConfig] = []

    func lint(config: TuistConfig) throws {
        lintArgs.append(config)
        if let error = lintStub {
            throw error
        }
    }
}
