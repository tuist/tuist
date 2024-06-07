import Foundation
import Path

@testable import XcodeGraph

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
