@testable import TuistKit
import Foundation

final class MockUpLinter: UpLinting {

    var lintCount: UInt = 0
    var lintStub: ((Upping) -> [LintingIssue])?

    func lint(up: Upping) -> [LintingIssue] {
        lintCount += 1
        return lintStub?(up) ?? []
    }
}
