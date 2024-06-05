import Foundation
import ProjectDescription
import TuistCore
import XcodeGraph

extension XcodeGraph.FrameworkStatus {
    /// Maps a ProjectDescription.FrameworkStatus instance into a XcodeGraph.FrameworkStatus instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of the framework status model.
    static func from(manifest: ProjectDescription.FrameworkStatus) -> XcodeGraph.FrameworkStatus {
        switch manifest {
        case .required:
            return .required
        case .optional:
            return .optional
        }
    }
}
