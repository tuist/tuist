import Foundation
import TuistCore
import TuistGraph
import TuistGraphTesting
import TuistSupport
@testable import TuistGenerator

class MockTargetLinter: TargetLinting {
    func lint(target _: Target) -> [LintingIssue] {
        []
    }
}
