import Foundation
import TSCBasic
@testable import TuistCore

public extension TargetScript {
    static func test(name: String = "Test",
                     script: String = "") -> TargetScript
    {
        TargetScript(name: name, script: script)
    }
}
