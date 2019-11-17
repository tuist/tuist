import Foundation
import TuistCore
import TuistSupport
@testable import TuistGenerator

class MockTargetLinter: TargetLinting {
    func lint(target _: Target) -> [LintingIssue] {
        return []
    }
}
