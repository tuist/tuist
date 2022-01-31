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
            return .enabled(.from(manifest: options))
        }
    }
}
