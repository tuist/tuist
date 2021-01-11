import Foundation
import TuistCore
import TuistSupport
@testable import TuistGenerator

class MockPackageLinter: PackageLinting {
    func lint(_: Package) -> [LintingIssue] {
        []
    }
}
