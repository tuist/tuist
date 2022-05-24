import ProjectDescription
import TuistGraph

extension ProjectDescription.Project.ProjectConfiguration {
    /// Maps a TuistGraph.Project.ProjectConfiguration instance into a ProjectDescription.Project.ProjectConfiguration instance.
    /// - Parameters:
    ///   - manifest: See ProjectConfiguration
    static func from(manifest: TuistGraph.Project.ProjectConfiguration) throws -> Self {
        let options = ProjectDescription.Project.Options.from(manifest: manifest.options)

        /// TODO: Ignore `resourceSynthesizers` param for now as it requires us to expose some dependencies
        /// from `TuistLoader`. Also, mapping from `.file` to `.plugin` isn't straightforward. This work can be
        /// done incrementally in another PR
        return .configuration(options: options, resourceSynthesizers: .default)
    }
}
