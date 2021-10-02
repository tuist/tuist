import Foundation
import ProjectDescription
import TuistGraph

extension CodeCoverageMode {
    static func from(
        manifest: ProjectDescription.Config.GenerationOptions.CodeCoverageMode,
        generatorPaths: GeneratorPaths
    ) throws -> CodeCoverageMode {
        switch manifest {
        case .all: return .all
        case .relevant: return .relevant
        case let .targets(targets):
            let targets: [TuistGraph.TargetReference] = try targets.map {
                .init(
                    projectPath: try generatorPaths.resolveSchemeActionProjectPath($0.projectPath),
                    name: $0.targetName
                )
            }
            return .targets(targets)
        }
    }
}
