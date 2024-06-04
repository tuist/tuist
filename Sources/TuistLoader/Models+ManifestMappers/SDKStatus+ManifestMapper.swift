import Foundation
import ProjectDescription
import TuistCore
import XcodeProjectGenerator

extension XcodeProjectGenerator.SDKStatus {
    /// Maps a ProjectDescription.SDKStatus instance into a XcodeProjectGenerator.SDKStatus instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of SDK status model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.SDKStatus) -> XcodeProjectGenerator.SDKStatus {
        switch manifest {
        case .required:
            return .required
        case .optional:
            return .optional
        }
    }
}
