import Foundation
import TuistCore
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
