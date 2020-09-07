import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport

extension TuistCore.DefaultSettings {
    /// Maps a ProjectDescription.DefaultSettings instance into a TuistCore.DefaultSettings model.
    /// - Parameters:
    ///   - manifest: Manifest representation of default settings.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.DefaultSettings) -> TuistCore.DefaultSettings {
        switch manifest {
        case .recommended(let excludedKeys):
            return .recommended(excludedKeys)
        case .essential(let excludedKeys):
            return .essential(excludedKeys)
        case .none:
            return .none
        }
    }
}
