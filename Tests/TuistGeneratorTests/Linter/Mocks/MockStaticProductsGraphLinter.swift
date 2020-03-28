import Foundation
import TuistCore
@testable import TuistGenerator

class MockStaticProductsGraphLinter: StaticProductsGraphLinting {
    var lintStub: ((Graph) -> [LintingIssue])?
    func lint(graph: Graph) -> [LintingIssue] {
        lintStub?(graph) ?? []
    }
}
