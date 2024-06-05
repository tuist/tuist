import Foundation
import TuistCore
import TuistSupport
import XcodeGraph
import XcodeGraphTesting
@testable import TuistGenerator

class MockPackageLinter: PackageLinting {
    func lint(_: Package) -> [LintingIssue] {
        []
    }
}
