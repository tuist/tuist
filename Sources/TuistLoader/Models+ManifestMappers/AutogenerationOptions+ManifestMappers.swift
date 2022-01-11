import Foundation
import ProjectDescription
import TuistGraph

extension AutogenerationOptions {
    static func from(manifest: ProjectDescription.Config.GenerationOptions.AutogenerationOptions) throws -> AutogenerationOptions
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
    ) throws -> Self {
        return .init(
            parallelizable: manifest.parallelizable,
            randomExecutionOrdering: manifest.randomExecutionOrdering,
            targetGroupSuffixes: .from(manifest: manifest.customTargetGroupSuffixes)
        )
    }
}

extension AutogenerationOptions.TestingOptions.TargetGroupSuffixes {
    static func from(
        manifest: ProjectDescription.Config.GenerationOptions.AutogenerationOptions.TestingOptions.TargetGroupSuffixes
    ) -> Self {
        return .init(build: manifest.build, test: manifest.test, run: manifest.run)
    }
}
