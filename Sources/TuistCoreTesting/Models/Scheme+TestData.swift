import Basic
import Foundation
@testable import TuistCore

public extension Scheme {
    static func test(name: String = "Test",
                     shared: Bool = false,
                     buildAction: BuildAction? = BuildAction.test(),
                     testAction: TestAction? = TestAction.test(),
                     runAction: RunAction? = RunAction.test(),
                     archiveAction: ArchiveAction? = ArchiveAction.test()) -> Scheme {
        Scheme(name: name,
               shared: shared,
               buildAction: buildAction,
               testAction: testAction,
               runAction: runAction,
               archiveAction: archiveAction)
    }
}
