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
            let path: AbsolutePath
            if let projectPath = executable.projectPath {
                path = try generatorPaths.resolve(path: projectPath)
            } else {
                path = generatorPaths.manifestDirectory
            }
            executableResolved = TargetReference(projectPath: path, name: executable.targetName)
        }

        self.init(configurationName: configurationName,
                  executable: executableResolved,
                  arguments: arguments)
    }
}
