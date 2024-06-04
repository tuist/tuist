import Foundation
import TuistCore
import XcodeProjectGenerator
import XcodeProjectGeneratorTesting
import TuistSupport
@testable import TuistGenerator

class MockPackageLinter: PackageLinting {
    func lint(_: Package) -> [LintingIssue] {
        []
    }
}
