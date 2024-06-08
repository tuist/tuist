import Foundation
import Path
import ProjectDescription
import TuistCore
import TuistSupport
import XcodeGraph

extension XcodeGraph.DefaultSettings {
    /// Maps a ProjectDescription.DefaultSettings instance into a XcodeGraph.DefaultSettings model.
    /// - Parameters:
    ///   - manifest: Manifest representation of default settings.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.DefaultSettings) -> XcodeGraph.DefaultSettings {
        switch manifest {
        case let .recommended(excludedKeys):
            return .recommended(excluding: excludedKeys)
        case let .essential(excludedKeys):
            return .essential(excluding: excludedKeys)
        case .none:
            return .none
        }
    }
}
