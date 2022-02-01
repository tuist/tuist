import ProjectDescription
import TuistGraph

extension TuistGraph.TestingOptions {
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
