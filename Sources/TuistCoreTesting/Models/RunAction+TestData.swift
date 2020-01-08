import Basic
import Foundation
@testable import TuistCore

public extension RunAction {
    static func test(configurationName: String = BuildConfiguration.debug.name,
                     executable: TargetReference? = TargetReference(projectPath: "/Project", name: "App"),
                     arguments: Arguments? = Arguments.test()) -> RunAction {
        RunAction(configurationName: configurationName,
                  executable: executable,
                  arguments: arguments)
    }
}
