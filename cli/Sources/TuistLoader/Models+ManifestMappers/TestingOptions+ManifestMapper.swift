import ProjectDescription
import XcodeGraph

extension XcodeGraph.TestingOptions {
    /// Maps a ProjectDescription.TestingOptions instance into a XcodeGraph.TestingOptions instance.
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
