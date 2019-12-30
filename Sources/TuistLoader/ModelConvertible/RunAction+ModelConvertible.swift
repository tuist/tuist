import Basic
import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.RunAction: ModelConvertible {
    init(manifest: ProjectDescription.RunAction, generatorPaths: GeneratorPaths) throws {
        let configurationName = manifest.configurationName
        let arguments = try manifest.arguments.map { try TuistCore.Arguments(manifest: $0, generatorPaths: generatorPaths) }

        var executableResolved: TuistCore.TargetReference?
        if let executable = manifest.executable {
            let path = try generatorPaths.resolve(projectPath: executable.projectPath)
            executableResolved = TargetReference(projectPath: path, name: executable.targetName)
        }

        self.init(configurationName: configurationName,
                  executable: executableResolved,
                  arguments: arguments)
    }
}
