import Foundation
import TuistCore
import TuistSupport
import TuistGraph
import TuistGraphTesting
@testable import TuistGenerator

class MockTargetLinter: TargetLinting {
    func lint(target _: Target) -> [LintingIssue] {
        []
    }
}
