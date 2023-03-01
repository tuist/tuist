import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph

extension TuistGraph.RunAction {
    /// Maps a ProjectDescription.RunAction instance into a TuistGraph.RunAction instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of  the settings.
    ///   - generatorPaths: Generator paths.
    static func from(
        manifest: ProjectDescription.RunAction,
        generatorPaths: GeneratorPaths
    ) throws -> TuistGraph.RunAction {
        let configurationName = manifest.configuration.rawValue

        let customLLDBInitFile = try manifest.customLLDBInitFile.map {
            try generatorPaths.resolve(path: $0)
        }

        let preActions = try manifest.preActions.map {
            try TuistGraph.ExecutionAction.from(
                manifest: $0,
                generatorPaths: generatorPaths
            )
        }

        let postActions = try manifest.postActions.map {
            try TuistGraph.ExecutionAction.from(
                manifest: $0,
                generatorPaths: generatorPaths
            )
        }

        let arguments = manifest.arguments.map { TuistGraph.Arguments.from(manifest: $0) }

        var executableResolved: TuistGraph.TargetReference?
        if let executable = manifest.executable {
            executableResolved = TargetReference(
                projectPath: try generatorPaths.resolveSchemeActionProjectPath(executable.projectPath),
                name: executable.targetName
            )
        }

        let options = try TuistGraph.RunActionOptions.from(manifest: manifest.options, generatorPaths: generatorPaths)

        let diagnosticsOptions = Set(manifest.diagnosticsOptions.map { TuistGraph.SchemeDiagnosticsOption.from(manifest: $0) })

        return TuistGraph.RunAction(
            configurationName: configurationName,
            attachDebugger: manifest.attachDebugger,
            customLLDBInitFile: customLLDBInitFile,
            preActions: preActions,
            postActions: postActions,
            executable: executableResolved,
            filePath: nil,
            arguments: arguments,
            options: options,
            diagnosticsOptions: diagnosticsOptions
        )
    }
}
