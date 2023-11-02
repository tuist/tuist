import Foundation
import ProjectDescription
import TuistCore
import TuistGraph

extension TuistGraph.FrameworkStatus {
    /// Maps a ProjectDescription.FrameworkStatus instance into a TuistGraph.FrameworkStatus instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of the framework status model.
    static func from(manifest: ProjectDescription.FrameworkStatus) -> TuistGraph.FrameworkStatus {
        switch manifest {
        case .required:
            return .required
        case .optional:
            return .optional
        }
    }
}
