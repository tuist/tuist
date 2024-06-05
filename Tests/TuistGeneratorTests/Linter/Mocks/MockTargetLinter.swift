import Foundation
import TuistCore
import TuistSupport
import XcodeGraph
import XcodeGraphTesting
@testable import TuistGenerator

class MockTargetLinter: TargetLinting {
    func lint(target _: Target) -> [LintingIssue] {
        []
    }
}
