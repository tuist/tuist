import Foundation
import TuistCore
import XcodeProjectGenerator
import XcodeProjectGeneratorTesting
import TuistSupport
@testable import TuistGenerator

class MockSettingsLinter: SettingsLinting {
    func lint(project _: Project) -> [LintingIssue] {
        []
    }

    func lint(target _: Target) -> [LintingIssue] {
        []
    }
}
