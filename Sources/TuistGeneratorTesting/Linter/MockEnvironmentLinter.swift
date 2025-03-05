import Foundation
import TuistCore

@testable import TuistGenerator

public final class MockEnvironmentLinter: EnvironmentLinting {
    public var lintStub: [LintingIssue]?
    public var lintArgs: [TuistGeneratedProjectOptions] = []

    public init() {}

    public func lint(configGeneratedProjectOptions: TuistGeneratedProjectOptions) throws -> [LintingIssue] {
        lintArgs.append(configGeneratedProjectOptions)
        return lintStub ?? []
    }
}
