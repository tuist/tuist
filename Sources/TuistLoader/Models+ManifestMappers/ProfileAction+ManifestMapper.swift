import Foundation
import ProjectDescription
import TSCBasic
import TuistCore

extension TuistCore.ProfileAction {
    static func from(manifest: ProjectDescription.ProfileAction,
                     generatorPaths: GeneratorPaths) throws -> TuistCore.ProfileAction
    {
        let configurationName = manifest.configurationName
        let arguments = manifest.arguments.map { TuistCore.Arguments.from(manifest: $0) }

        var executableResolved: TuistCore.TargetReference?
        if let executable = manifest.executable {
            executableResolved = TargetReference(projectPath: try generatorPaths.resolveSchemeActionProjectPath(executable.projectPath),
                                                 name: executable.targetName)
        }

        return ProfileAction(configurationName: configurationName,
                             executable: executableResolved,
                             arguments: arguments)
    }
}
