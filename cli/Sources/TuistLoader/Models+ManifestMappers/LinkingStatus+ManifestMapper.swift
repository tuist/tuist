import Foundation
import ProjectDescription
import TuistCore
import XcodeGraph

extension XcodeGraph.LinkingStatus {
    /// Maps a ProjectDescription.LinkingStatus instance into a XcodeGraph.LinkingStatus instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of the framework status model.
    static func from(manifest: ProjectDescription.LinkingStatus) -> XcodeGraph.LinkingStatus {
        switch manifest {
        case .required:
            return .required
        case .optional:
            return .optional
        case .none:
            return .none
        }
    }
}
