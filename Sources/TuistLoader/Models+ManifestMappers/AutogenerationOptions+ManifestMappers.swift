import Foundation
import ProjectDescription
import TuistGraph

extension AutogenerationOptions {
    static func from(manifest: ProjectDescription.Config.GenerationOptions
        .AutogenerationOptions) throws -> AutogenerationOptions
    {
        switch manifest {
        case .disabled:
            return .disabled
        case let .enabled(options):
            return .enabled(try .from(manifest: options))
        }
    }
}

extension AutogenerationOptions.TestingOptions {
    static func from(
        manifest: ProjectDescription.Config.GenerationOptions.AutogenerationOptions.TestingOptions
    ) throws -> AutogenerationOptions.TestingOptions {
        var options: AutogenerationOptions.TestingOptions = []

        if manifest.contains(.parallelizable) {
            options.insert(.parallelizable)
        }

        if manifest.contains(.randomExecutionOrdering) {
            options.insert(.randomExecutionOrdering)
        }

        return options
    }
}
