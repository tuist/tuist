import Foundation
import Path
import ProjectDescription
import XcodeGraph

extension XcodeGraph.ExecutionAction {
    /// Maps a ProjectDescription.ExecutionAction instance into a XcodeGraph.ExecutionAction instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of execution action model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.ExecutionAction, generatorPaths: GeneratorPaths) throws -> XcodeGraph
        .ExecutionAction
    {
        let targetReference: XcodeGraph.TargetReference? = try manifest.target.map {
            .init(
                projectPath: try generatorPaths.resolveSchemeActionProjectPath($0.projectPath),
                name: $0.targetName
            )
        }
        return ExecutionAction(
            title: manifest.title,
            scriptText: manifest.scriptText,
            target: targetReference,
            shellPath: manifest.shellPath
        )
    }
}
