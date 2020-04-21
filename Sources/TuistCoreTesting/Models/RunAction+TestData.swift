import Foundation
import TSCBasic
@testable import TuistCore

public extension RunAction {
    static func test(configurationName: String = BuildConfiguration.debug.name,
                     executable: TargetReference? = TargetReference(projectPath: "/Project", name: "App"),
                     filePath: AbsolutePath? = nil,
                     arguments: Arguments? = Arguments.test()) -> RunAction {
        RunAction(configurationName: configurationName,
                  executable: executable,
                  filePath: filePath,
                  arguments: arguments)
    }
}
