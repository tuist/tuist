import ProjectDescription
import TuistGraph

extension ProjectDescription.Project.Configuration {
    /// Maps a TuistGraph.Project.Configuration instance into a ProjectDescription.Project.Configuration instance.
    /// - Parameters:
    ///   - manifest: See Project.Configuration
    static func from(manifest: TuistGraph.Project.Configuration) -> Self {
        .configuration(
            options: .from(manifest: manifest.options)
        )
    }
}
