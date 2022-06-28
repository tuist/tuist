import ProjectDescription
import TuistGraph

extension ProjectDescription.TestingOptions {
    /// Maps a TuistGraph.TestingOptions instance into a ProjectDescription.TestingOptions instance.
    /// - Parameters:
    /// - manifest: Manifest representation of testing options.
    static func from(
        manifest: TuistGraph.TestingOptions
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
