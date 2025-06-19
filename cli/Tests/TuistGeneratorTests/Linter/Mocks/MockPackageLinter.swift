import Foundation
import TuistCore
import TuistSupport
import XcodeGraph
@testable import TuistGenerator

class MockPackageLinter: PackageLinting {
    func lint(_: Package) -> [LintingIssue] {
        []
    }
}
