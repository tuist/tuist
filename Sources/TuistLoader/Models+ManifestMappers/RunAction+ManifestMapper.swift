import Foundation
import ProjectDescription
import TSCBasic
import TuistCore

extension TuistCore.RunAction {
    /// Maps a ProjectDescription.RunAction instance into a TuistCore.RunAction instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of  the settings.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.RunAction,
                     generatorPaths: GeneratorPaths) throws -> TuistCore.RunAction
    {
        let configurationName = manifest.configurationName
        let arguments = manifest.arguments.map { TuistCore.Arguments.from(manifest: $0) }

        var executableResolved: TuistCore.TargetReference?
        if let executable = manifest.executable {
            executableResolved = TargetReference(projectPath: try generatorPaths.resolveSchemeActionProjectPath(executable.projectPath),
                                                 name: executable.targetName)
        }
        let diagnosticsOptions = Set(manifest.diagnosticsOptions.map { TuistCore.SchemeDiagnosticsOption.from(manifest: $0) })
        return TuistCore.RunAction(configurationName: configurationName,
                                   executable: executableResolved,
                                   filePath: nil,
                                   arguments: arguments,
                                   diagnosticsOptions: diagnosticsOptions)
    }
}
