import Foundation
import TuistCore
import TuistDependencies
import TuistGenerator

/// The GraphMapperFactorying describes the interface of a factory of graph mappers.
/// Methods in the interface map with workflows exposed to the user.
protocol GraphMapperFactorying {
    ///  Returns the graph mapper that should be used for automation tasks such as build and test.
    /// - Returns: A graph mapper.
    func automation(
        config: Tuist,
        testPlan: String?,
        includedTargets: Set<TargetQuery>,
        excludedTargets: Set<TargetQuery>
    ) -> [GraphMapping]

    /// Returns the default graph mapper that should be used from all the commands that require loading and processing the graph.
    /// - Returns: The default mapper.
    func `default`(
        config: Tuist
    ) -> [GraphMapping]
}

public final class GraphMapperFactory: GraphMapperFactorying {
    public init() {}

    public func automation(
        config: Tuist,
        testPlan: String?,
        includedTargets: Set<TargetQuery>,
        excludedTargets: Set<TargetQuery>
    ) -> [GraphMapping] {
        var mappers: [GraphMapping] = []
        mappers.append(
            FocusTargetsGraphMappers(
                testPlan: testPlan,
                includedTargets: includedTargets,
                excludedTargets: excludedTargets
            )
        )
        mappers.append(TreeShakePrunedTargetsGraphMapper())
        mappers.append(contentsOf: self.default(config: config))

        return mappers
    }

    public func `default`(
        config: Tuist
    ) -> [GraphMapping] {
        var mappers: [GraphMapping] = []
        mappers.append(ModuleMapMapper())
        mappers.append(UpdateWorkspaceProjectsGraphMapper())
        mappers.append(ExternalProjectsPlatformNarrowerGraphMapper())
        mappers.append(PruneOrphanExternalTargetsGraphMapper())
        if config.project.generatedProject?.generationOptions.enforceExplicitDependencies == true {
            mappers.append(ExplicitDependencyGraphMapper())
        }
        mappers.append(TreeShakePrunedTargetsGraphMapper())
        mappers.append(StaticXCFrameworkModuleMapGraphMapper())
        return mappers
    }
}
