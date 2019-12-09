import Foundation
import TuistCore
import TuistCoreTesting
import TuistSupport
@testable import TuistGenerator

class MockGraphLinter: GraphLinting {
    func lint(graph _: Graphing) -> [LintingIssue] {
        []
    }
}
