import Foundation
import TSCBasic
@testable import TuistGraph

public extension RawScriptBuildPhase {
    static func test(name: String = "Test",
                     script: String = "",
                     showEnvVarsInLog: Bool = false,
                     hashable: Bool = false) -> RawScriptBuildPhase
    {
        RawScriptBuildPhase(name: name, script: script, showEnvVarsInLog: showEnvVarsInLog, hashable: hashable)
    }
}
