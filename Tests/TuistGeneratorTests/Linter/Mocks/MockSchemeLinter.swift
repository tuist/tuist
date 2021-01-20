import Foundation
import TuistCore
import TuistSupport
import TuistGraph
import TuistGraphTesting
@testable import TuistGenerator

class MockSchemeLinter: SchemeLinting {
    func lint(project _: Project) -> [LintingIssue] {
        []
    }
}
