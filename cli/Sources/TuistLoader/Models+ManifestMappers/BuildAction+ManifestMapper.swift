import Foundation
import ProjectDescription
import TuistCore
import XcodeGraph

extension XcodeGraph.BuildAction {
    /// Maps a ProjectDescription.BuildAction instance into a XcodeGraph.BuildAction instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of build action model.
    ///   - generatorPaths: Generator paths.
    static func from(
        manifest: ProjectDescription.BuildAction,
        generatorPaths: GeneratorPaths
    ) throws -> XcodeGraph.BuildAction {
        let parallelizeBuild = manifest.buildOrder == .dependency
        let preActions = try manifest.preActions.map { try XcodeGraph.ExecutionAction.from(
            manifest: $0,
            generatorPaths: generatorPaths
        ) }
        let postActions = try manifest.postActions.map { try XcodeGraph.ExecutionAction.from(
            manifest: $0,
            generatorPaths: generatorPaths
        ) }
        var seenTargets: Set<XcodeGraph.TargetReference> = []
        let targets: [XcodeGraph.TargetReference] = try manifest.targets.map {
            XcodeGraph.TargetReference(
                projectPath: try generatorPaths.resolveSchemeActionProjectPath($0.projectPath),
                name: $0.targetName
            )
        }.filter { seenTargets.insert($0).inserted }
        let buildFor = try mapBuildFor(
            manifest.buildFor,
            generatorPaths: generatorPaths
        )
        return XcodeGraph.BuildAction(
            targets: targets,
            buildFor: buildFor,
            preActions: preActions,
            postActions: postActions,
            parallelizeBuild: parallelizeBuild,
            runPostActionsOnFailure: manifest.runPostActionsOnFailure,
            findImplicitDependencies: manifest.findImplicitDependencies
        )
    }
}

extension XcodeGraph.BuildAction {
    fileprivate static func mapBuildFor(
        _ buildFor: [ProjectDescription.TargetReference: Set<ProjectDescription.BuildActionTarget.BuildFor>],
        generatorPaths: GeneratorPaths
    ) throws -> [XcodeGraph.TargetReference: Set<XcodeGraph.BuildAction.BuildFor>] {
        let keyValuePairs = try buildFor.map { targetReference, buildForOptions in
            let graphTargetReference = XcodeGraph.TargetReference(
                projectPath: try generatorPaths.resolveSchemeActionProjectPath(targetReference.projectPath),
                name: targetReference.targetName
            )
            let graphBuildForOptions = Set(buildForOptions.map(\.graphBuildFor))

            return (graphTargetReference, graphBuildForOptions)
        }

        return Dictionary(
            keyValuePairs,
            uniquingKeysWith: { existing, duplicate in existing.union(duplicate) }
        )
    }
}

extension ProjectDescription.BuildActionTarget.BuildFor {
    fileprivate var graphBuildFor: XcodeGraph.BuildAction.BuildFor {
        switch self {
        case .analyzing:
            return .analyzing
        case .archiving:
            return .archiving
        case .profiling:
            return .profiling
        case .running:
            return .running
        case .testing:
            return .testing
        }
    }
}
