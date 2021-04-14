import Foundation
import TuistCore
import TuistGraph
import TuistGraphTesting
import TuistSupport
@testable import TuistGenerator

class MockPackageLinter: PackageLinting {
    func lint(_: Package) -> [LintingIssue] {
        []
    }
}
