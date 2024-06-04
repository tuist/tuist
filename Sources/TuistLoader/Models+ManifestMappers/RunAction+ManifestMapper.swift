import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import XcodeProjectGenerator

extension XcodeProjectGenerator.RunAction {
    /// Maps a ProjectDescription.RunAction instance into a XcodeProjectGenerator.RunAction instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of  the settings.
    ///   - generatorPaths: Generator paths.
    static func from(
        manifest: ProjectDescription.RunAction,
        generatorPaths: GeneratorPaths
    ) throws -> XcodeProjectGenerator.RunAction {
        let configurationName = manifest.configuration.rawValue

        let customLLDBInitFile = try manifest.customLLDBInitFile.map {
            try generatorPaths.resolve(path: $0)
        }

        let preActions = try manifest.preActions.map {
            try XcodeProjectGenerator.ExecutionAction.from(
                manifest: $0,
                generatorPaths: generatorPaths
            )
        }

        let postActions = try manifest.postActions.map {
            try XcodeProjectGenerator.ExecutionAction.from(
                manifest: $0,
                generatorPaths: generatorPaths
            )
        }

        let arguments = manifest.arguments.map { XcodeProjectGenerator.Arguments.from(manifest: $0) }

        var executableResolved: XcodeProjectGenerator.TargetReference?
        if let executable = manifest.executable {
            executableResolved = TargetReference(
                projectPath: try generatorPaths.resolveSchemeActionProjectPath(executable.projectPath),
                name: executable.targetName
            )
        }

        let options = try XcodeProjectGenerator.RunActionOptions.from(manifest: manifest.options, generatorPaths: generatorPaths)

        let diagnosticsOptions = XcodeProjectGenerator.SchemeDiagnosticsOptions.from(manifest: manifest.diagnosticsOptions)

        let expandVariablesFromTarget: XcodeProjectGenerator.TargetReference?
        expandVariablesFromTarget = try manifest.expandVariableFromTarget.map {
            XcodeProjectGenerator.TargetReference(
                projectPath: try generatorPaths.resolveSchemeActionProjectPath($0.projectPath),
                name: $0.targetName
            )
        }

        let launchStyle = XcodeProjectGenerator.LaunchStyle.from(manifest: manifest.launchStyle)

        return XcodeProjectGenerator.RunAction(
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
