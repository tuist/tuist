import Foundation
import TuistCore
import XcodeProjectGenerator
import XcodeProjectGeneratorTesting
import TuistSupport
@testable import TuistGenerator

class MockTargetLinter: TargetLinting {
    func lint(target _: Target) -> [LintingIssue] {
        []
    }
}
