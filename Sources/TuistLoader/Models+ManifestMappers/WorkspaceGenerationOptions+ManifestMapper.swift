import Foundation
import ProjectDescription
import TuistGraph

extension TuistGraph.Workspace.GenerationOptions {
    /// Maps ProjectDescription.Workspace.GenerationOptions instance into a TuistGraph.Workspace.GenerationOptions model.
    /// - Parameters:
    ///   - manifest: Manifest representation of a generation option.
    static func from(manifest: ProjectDescription.Workspace.GenerationOptions) -> Self {
        switch manifest {
        case let .automaticSchemaGeneration(behavior):
            return .automaticSchemaGeneration(.from(manifest: behavior))
        }
    }
}

extension TuistGraph.Workspace.GenerationOptions.AutomaticSchemaGeneration {
    /// Maps ProjectDescription.Workspace.AutomaticSchemaGeneration instance into a TuistGraph.Workspace.AutomaticSchemaGeneration model.
    /// - Parameters:
    ///   - manifest: Manifest representation of a schema generation option.
    static func from(manifest: ProjectDescription.Workspace.GenerationOptions.AutomaticSchemaGeneration) -> Self {
        switch manifest {
        case .default: return .default
        case .disabled: return .disabled
        case .enabled: return .enabled
        }
    }
}
