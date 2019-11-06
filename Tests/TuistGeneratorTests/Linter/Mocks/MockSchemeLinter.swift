import Foundation
import TuistSupport
@testable import TuistGenerator

class MockSchemeLinter: SchemeLinting {
    func lint(project _: Project) -> [LintingIssue] {
        return []
    }
}
