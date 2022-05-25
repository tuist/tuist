import ProjectDescription
import TuistGraph

extension ProjectDescription.Project.ProjectConfiguration {
    /// Maps a TuistGraph.Project.ProjectConfiguration instance into a ProjectDescription.Project.ProjectConfiguration instance.
    /// - Parameters:
    ///   - manifest: See ProjectConfiguration
    static func from(manifest: TuistGraph.Project.ProjectConfiguration) throws -> Self {
        .configuration(
            options: .from(manifest: manifest.options)
        )
    }
}
