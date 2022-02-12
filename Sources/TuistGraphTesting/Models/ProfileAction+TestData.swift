import Foundation
import TSCBasic
@testable import TuistGraph

extension ProfileAction {
    public static func test(
        configurationName: String = "Beta Release",
        preActions: [ExecutionAction] = [],
        postActions: [ExecutionAction] = [],
        executable: TargetReference? = TargetReference(projectPath: "/Project", name: "App"),
        arguments: Arguments? = Arguments.test()
    ) -> ProfileAction {
        ProfileAction(
            configurationName: configurationName,
            preActions: preActions,
            postActions: postActions,
            executable: executable,
            arguments: arguments
        )
    }
}
