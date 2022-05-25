import ProjectDescription
import TuistGraph

extension TuistGraph.Project.ProjectConfiguration {
    /// Maps a ProjectDescription.Project.ProjectConfiguration instance into a TuistGraph.Project.ProjectConfiguration instance.
    /// - Parameters:
    ///   - manifest: See ProjectConfiguration
    ///   - generatorPaths: See GeneratorPaths
    ///   - plugins: See Plugins
    ///   - resourceSynthesizerPathLocator: See ResourceSynthesizerPathLocating
    static func from(manifest: ProjectDescription.Project.ProjectConfiguration) throws -> Self {
        .configuration(options: .from(manifest: manifest.options))
    }
}
