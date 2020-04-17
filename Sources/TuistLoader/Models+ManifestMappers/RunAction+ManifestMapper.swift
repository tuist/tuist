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
                     generatorPaths: GeneratorPaths) throws -> TuistCore.RunAction {
        let configurationName = manifest.configurationName
        let arguments = manifest.arguments.map { TuistCore.Arguments.from(manifest: $0) }

        var executableResolved: TuistCore.TargetReference?
        if let executable = manifest.executable {
            executableResolved = TargetReference(projectPath: try generatorPaths.resolveSchemeActionProjectPath(executable.projectPath),
                                                 name: executable.targetName)
        }

        return RunAction(configurationName: configurationName,
                         executable: executableResolved,
                         arguments: arguments)
    }
}
