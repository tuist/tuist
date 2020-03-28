import Foundation
import TuistCore
import TuistCoreTesting
import TuistSupport
@testable import TuistGenerator

public class MockGraphLinter: GraphLinting {
    public var lintStub: [LintingIssue]?

    public init() {}

    public func lint(graph _: Graph) -> [LintingIssue] {
        lintStub ?? []
    }
}
