import Foundation
import Path
import ProjectDescription
import TuistCore
import XcodeGraph

extension XcodeGraph.RunAction {
    /// Maps a ProjectDescription.RunAction instance into a XcodeGraph.RunAction instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of  the settings.
    ///   - generatorPaths: Generator paths.
    static func from(
        manifest: ProjectDescription.RunAction,
        generatorPaths: GeneratorPaths
    ) throws -> XcodeGraph.RunAction {
        let configurationName = manifest.configuration.rawValue

        let customLLDBInitFile = try manifest.customLLDBInitFile.map {
            try generatorPaths.resolve(path: $0)
        }

        let preActions = try manifest.preActions.map {
            try XcodeGraph.ExecutionAction.from(
                manifest: $0,
                generatorPaths: generatorPaths
            )
        }

        let postActions = try manifest.postActions.map {
            try XcodeGraph.ExecutionAction.from(
                manifest: $0,
                generatorPaths: generatorPaths
            )
        }

        let arguments = manifest.arguments.map { XcodeGraph.Arguments.from(manifest: $0) }

        var executableResolved: XcodeGraph.TargetReference?
        if let executable = manifest.executable {
            executableResolved = TargetReference(
                projectPath: try generatorPaths.resolveSchemeActionProjectPath(executable.projectPath),
                name: executable.targetName
            )
        }

        let options = try XcodeGraph.RunActionOptions.from(manifest: manifest.options, generatorPaths: generatorPaths)

        let diagnosticsOptions = XcodeGraph.SchemeDiagnosticsOptions.from(manifest: manifest.diagnosticsOptions)

        let expandVariablesFromTarget: XcodeGraph.TargetReference?
        expandVariablesFromTarget = try manifest.expandVariableFromTarget.map {
            XcodeGraph.TargetReference(
                projectPath: try generatorPaths.resolveSchemeActionProjectPath($0.projectPath),
                name: $0.targetName
            )
        }

        let launchStyle = XcodeGraph.LaunchStyle.from(manifest: manifest.launchStyle)

        return XcodeGraph.RunAction(
            configurationName: configurationName,
            attachDebugger: manifest.attachDebugger,
            customLLDBInitFile: customLLDBInitFile,
            preActions: preActions,
            postActions: postActions,
            executable: executableResolved,
            filePath: nil,
            arguments: arguments,
            options: options,
            diagnosticsOptions: diagnosticsOptions,
            expandVariableFromTarget: expandVariablesFromTarget,
            launchStyle: launchStyle
        )
    }
}
