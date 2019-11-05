import Foundation
import TuistSupport
@testable import TuistGenerator

class MockTargetLinter: TargetLinting {
    func lint(target _: Target) -> [LintingIssue] {
        return []
    }
}
