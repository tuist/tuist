import Foundation
import TSCBasic
@testable import TuistCore

public extension TargetScript {
    static func test(name: String = "Test",
                     script: String = "",
                     showEnvVarsInLog: Bool = false,
                     hashable: Bool = false) -> TargetScript
    {
        TargetScript(name: name, script: script, showEnvVarsInLog: showEnvVarsInLog, hashable: hashable)
    }
}
