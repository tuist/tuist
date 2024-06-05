import Foundation
import TuistCore
import TuistSupport
import XcodeGraph
import XcodeGraphTesting
@testable import TuistGenerator

class MockSchemeLinter: SchemeLinting {
    func lint(project _: Project) -> [LintingIssue] {
        []
    }
}
