import Foundation
import TuistCore
import TuistSupport
import XcodeGraph
@testable import TuistGenerator

class MockTargetLinter: TargetLinting {
    func lint(target _: Target, options _: Project.Options) -> [LintingIssue] {
        []
    }
}
