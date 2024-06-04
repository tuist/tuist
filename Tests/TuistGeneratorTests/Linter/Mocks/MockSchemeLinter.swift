import Foundation
import TuistCore
import XcodeProjectGenerator
import XcodeProjectGeneratorTesting
import TuistSupport
@testable import TuistGenerator

class MockSchemeLinter: SchemeLinting {
    func lint(project _: Project) -> [LintingIssue] {
        []
    }
}
