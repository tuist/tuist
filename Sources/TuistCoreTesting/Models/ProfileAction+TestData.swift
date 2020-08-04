import Foundation
import TSCBasic
@testable import TuistCore

public extension ProfileAction {
    static func test(configurationName: String = "Beta Release",
                     executable: TargetReference? = TargetReference(projectPath: "/Project", name: "App"),
                     arguments: Arguments? = Arguments.test()) -> ProfileAction
    {
        ProfileAction(configurationName: configurationName,
                      executable: executable,
                      arguments: arguments)
    }
}
