import Foundation
import TSCBasic
@testable import TuistGraph

extension ProfileAction {
    public static func test(configurationName: String = "Beta Release",
                            executable: TargetReference? = TargetReference(projectPath: "/Project", name: "App"),
                            arguments: Arguments? = Arguments.test()) -> ProfileAction
    {
        ProfileAction(
            configurationName: configurationName,
            executable: executable,
            arguments: arguments
        )
    }
}
