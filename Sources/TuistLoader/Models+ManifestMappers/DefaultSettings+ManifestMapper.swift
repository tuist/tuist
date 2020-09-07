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
        case .recommended:
            return .recommended
        case .essential:
            return .essential
        case .excluding(let base, let excludedKeys):
            return .excluding(from(manifest: base), excludedKeys)
        case .none:
            return .none
        }
    }
}
