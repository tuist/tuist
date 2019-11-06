import Foundation
import TuistSupport
@testable import TuistGenerator

class MockSettingsLinter: SettingsLinting {
    func lint(project _: Project) -> [LintingIssue] {
        return []
    }

    func lint(target _: Target) -> [LintingIssue] {
        return []
    }
}
