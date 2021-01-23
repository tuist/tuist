import Foundation
import TuistCore
import TuistGraph
import TuistGraphTesting
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
