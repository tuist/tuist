import Foundation
import ProjectDescription
import TuistCore
import XcodeGraph

extension XcodeGraph.SDKStatus {
    /// Maps a ProjectDescription.SDKStatus instance into a XcodeGraph.SDKStatus instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of SDK status model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.SDKStatus) -> XcodeGraph.SDKStatus {
        switch manifest {
        case .required:
            return .required
        case .optional:
            return .optional
        }
    }
}
