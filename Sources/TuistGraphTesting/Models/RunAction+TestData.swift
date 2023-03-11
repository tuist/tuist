import Foundation
import TSCBasic
@testable import TuistGraph

extension RunAction {
    public static func test(
        configurationName: String = BuildConfiguration.debug.name,
        attachDebugger: Bool = true,
        customLLDBInitFile: AbsolutePath? = nil,
        preActions: [ExecutionAction] = [],
        postActions: [ExecutionAction] = [],
        executable: TargetReference? = TargetReference(projectPath: "/Project", name: "App"),
        filePath: AbsolutePath? = nil,
        arguments: Arguments? = Arguments.test(),
        options: RunActionOptions = .init(),
        diagnosticsOptions: Set<SchemeDiagnosticsOption> = [.mainThreadChecker, .performanceAntipatternChecker]
    ) -> RunAction {
        RunAction(
            configurationName: configurationName,
            attachDebugger: attachDebugger,
            customLLDBInitFile: customLLDBInitFile,
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
