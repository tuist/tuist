import Foundation
import TSCBasic
@testable import TuistCore

public extension BuildAction {
    static func test(targets: [TargetReference] = [TargetReference(projectPath: "/Project", name: "App")],
                     preActions: [ExecutionAction] = [],
                     postActions: [ExecutionAction] = []) -> BuildAction
    {
        BuildAction(targets: targets, preActions: preActions, postActions: postActions)
    }
}
