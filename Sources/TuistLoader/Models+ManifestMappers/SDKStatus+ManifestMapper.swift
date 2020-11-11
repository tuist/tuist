import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.SDKStatus {
    /// Maps a ProjectDescription.SDKStatus instance into a TuistCore.SDKStatus instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of SDK status model.
    ///   - pathResolver: Generator paths.
    static func from(manifest: ProjectDescription.SDKStatus) -> TuistCore.SDKStatus {
        switch manifest {
        case .required:
            return .required
        case .optional:
            return .optional
        }
    }
}
