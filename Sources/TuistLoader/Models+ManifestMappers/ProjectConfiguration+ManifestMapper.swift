import ProjectDescription
import TuistGraph

extension TuistGraph.Project.ProjectConfiguration {
    /// Maps a ProjectDescription.Project.ProjectConfiguration instance into a TuistGraph.Project.ProjectConfiguration instance.
    /// - Parameters:
    ///   - manifest: See ProjectConfiguration
    ///   - generatorPaths: See GeneratorPaths
    ///   - plugins: See Plugins
    ///   - resourceSynthesizerPathLocator: See ResourceSynthesizerPathLocating
    static func from(
        manifest: ProjectDescription.Project.ProjectConfiguration,
        generatorPaths: GeneratorPaths,
        plugins: Plugins,
        resourceSynthesizerPathLocator: ResourceSynthesizerPathLocating
    ) throws -> Self {
        let options = TuistGraph.Project.Options.from(manifest: manifest.options)
        let resourceSynthesizers = try manifest.resourceSynthesizers.map {
            try TuistGraph.ResourceSynthesizer.from(
                manifest: $0,
                generatorPaths: generatorPaths,
                plugins: plugins,
                resourceSynthesizerPathLocator: resourceSynthesizerPathLocator
            )
        }

        return .configuration(options: options, resourceSynthesizers: resourceSynthesizers)
    }
}
