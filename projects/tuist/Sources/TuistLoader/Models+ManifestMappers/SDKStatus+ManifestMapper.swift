import Foundation
import ProjectDescription
import TuistCore
import TuistGraph

extension TuistGraph.SDKStatus {
    /// Maps a ProjectDescription.SDKStatus instance into a TuistGraph.SDKStatus instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of SDK status model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.SDKStatus) -> TuistGraph.SDKStatus {
        switch manifest {
        case .required:
            return .required
        case .optional:
            return .optional
        }
    }
}
