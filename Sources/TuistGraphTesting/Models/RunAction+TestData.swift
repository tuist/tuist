import Foundation
import TSCBasic
@testable import TuistGraph

extension RunAction {
    public static func test(configurationName: String = BuildConfiguration.debug.name,
                            preActions: [ExecutionAction] = [],
                            postActions: [ExecutionAction] = [],
                            executable: TargetReference? = TargetReference(projectPath: "/Project", name: "App"),
                            filePath: AbsolutePath? = nil,
                            arguments: Arguments? = Arguments.test(),
                            options: RunActionOptions = .init(),
                            diagnosticsOptions: Set<SchemeDiagnosticsOption> = [.mainThreadChecker]) -> RunAction
    {
        RunAction(
            configurationName: configurationName,
            preActions: preActions,
            postActions: postActions,
            executable: executable,
            filePath: filePath,
            arguments: arguments,
            options: options,
            diagnosticsOptions: diagnosticsOptions
        )
    }
}
