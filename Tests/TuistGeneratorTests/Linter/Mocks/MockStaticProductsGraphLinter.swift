import Foundation
import TuistCore
@testable import TuistGenerator

class MockStaticProductsGraphLinter: StaticProductsGraphLinting {
    func lint(graph _: Graphing) -> [LintingIssue] {
        []
    }
}
