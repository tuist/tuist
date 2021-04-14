import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

extension TuistGraph.DefaultSettings {
    /// Maps a ProjectDescription.DefaultSettings instance into a TuistGraph.DefaultSettings model.
    /// - Parameters:
    ///   - manifest: Manifest representation of default settings.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.DefaultSettings) -> TuistGraph.DefaultSettings {
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
