import Foundation
import TSCBasic
@testable import TuistGraph

extension Scheme {
    public static func test(
        name: String = "Test",
        shared: Bool = false,
        buildAction: BuildAction? = BuildAction.test(),
        testAction: TestAction? = TestAction.test(),
        runAction: RunAction? = RunAction.test(),
        archiveAction: ArchiveAction? = ArchiveAction.test(),
        profileAction: ProfileAction? = ProfileAction.test(),
        analyzeAction: AnalyzeAction? = AnalyzeAction.test()
    ) -> Scheme {
        Scheme(
            name: name,
            shared: shared,
            buildAction: buildAction,
            testAction: testAction,
            runAction: runAction,
            archiveAction: archiveAction,
            profileAction: profileAction,
            analyzeAction: analyzeAction
        )
    }
}
