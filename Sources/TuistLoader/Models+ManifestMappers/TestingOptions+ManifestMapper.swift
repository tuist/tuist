import ProjectDescription
import TuistGraph

extension TuistGraph.TestingOptions {
    /// Maps a ProjectDescription.TestingOptions instance into a TuistGraph.TestingOptions instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of testing options.
    static func from(
        manifest: ProjectDescription.TestingOptions
    ) -> Self {
        var options: Self = []

        if manifest.contains(.parallelizable) {
            options.insert(.parallelizable)
        }

        if manifest.contains(.randomExecutionOrdering) {
            options.insert(.randomExecutionOrdering)
        }

        return options
    }
}
