import Foundation
import TuistCore
@testable import TuistGenerator

public final class MockEnvironmentLinter: EnvironmentLinting {
    public var lintStub: [LintingIssue]?
    public var lintArgs: [TuistConfig] = []

    public init() {}

    public func lint(config: TuistConfig) throws -> [LintingIssue] {
        lintArgs.append(config)
        return lintStub ?? []
    }
}
