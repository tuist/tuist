import Foundation
import ProjectDescription
import TuistGraph

extension TestingOptions {
    static func from(
        manifest: ProjectDescription.Config.GenerationOptions.TestingOptions
    ) throws -> TestingOptions {
        var options: TestingOptions = []

        if manifest.contains(.parallelizable) {
            options.insert(.parallelizable)
        }

        if manifest.contains(.randomExecutionOrdering) {
            options.insert(.randomExecutionOrdering)
        }

        return options
    }
}
