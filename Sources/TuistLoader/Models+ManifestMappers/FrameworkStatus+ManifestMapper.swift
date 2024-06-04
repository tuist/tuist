import Foundation
import ProjectDescription
import TuistCore
import XcodeProjectGenerator

extension XcodeProjectGenerator.FrameworkStatus {
    /// Maps a ProjectDescription.FrameworkStatus instance into a XcodeProjectGenerator.FrameworkStatus instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of the framework status model.
    static func from(manifest: ProjectDescription.FrameworkStatus) -> XcodeProjectGenerator.FrameworkStatus {
        switch manifest {
        case .required:
            return .required
        case .optional:
            return .optional
        }
    }
}
