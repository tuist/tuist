import Foundation
import TuistCore
import TuistGraph
import TuistGraphTesting
import TuistSupport
@testable import TuistGenerator

class MockSchemeLinter: SchemeLinting {
    func lint(project _: Project) -> [LintingIssue] {
        []
    }
}
