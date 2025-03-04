import Foundation
import TuistCore

@testable import TuistGenerator

public final class MockEnvironmentLinter: EnvironmentLinting {
    public var lintStub: [LintingIssue]?
    public var lintArgs: [Tuist] = []

    public init() {}

    public func lint(config: Tuist) throws -> [LintingIssue] {
        lintArgs.append(config)
        return lintStub ?? []
    }
}
