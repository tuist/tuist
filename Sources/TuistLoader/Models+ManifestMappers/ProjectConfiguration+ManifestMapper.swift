import ProjectDescription
import TuistGraph

extension TuistGraph.Project.Configuration {
    /// Maps a ProjectDescription.Project.Configuration instance into a TuistGraph.Project.Configuration instance.
    /// - Parameters:
    ///   - manifest: See Project.Configuration
    static func from(manifest: ProjectDescription.Project.Configuration) -> Self {
        .configuration(options: .from(manifest: manifest.options))
    }
}
