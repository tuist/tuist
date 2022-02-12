import Foundation
import TSCBasic

@testable import TuistGraph

extension GraphTarget {
    public static func test(
        path: AbsolutePath = .root,
        target: Target = .test(),
        project: Project = .test()
    ) -> GraphTarget {
        GraphTarget(
            path: path,
            target: target,
            project: project
        )
    }
}
