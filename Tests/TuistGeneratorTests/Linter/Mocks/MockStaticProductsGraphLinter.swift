import Foundation
import TuistCore
@testable import TuistGenerator

class MockStaticProductsGraphLinter: StaticProductsGraphLinting {
    var lintStub: ((Graphing) -> [LintingIssue])?
    func lint(graph: Graphing) -> [LintingIssue] {
        lintStub?(graph) ?? []
    }
}
