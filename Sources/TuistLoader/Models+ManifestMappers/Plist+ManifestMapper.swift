import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph

extension TuistGraph.Plist.Value {
    /// Maps a ProjectDescription.Plist.Value instance into a TuistGraph.Plist.Value instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of the Info plist value model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.Plist.Value) -> TuistGraph.Plist.Value {
        switch manifest {
        case let .string(value):
            return .string(value)
        case let .boolean(value):
            return .boolean(value)
        case let .integer(value):
            return .integer(value)
        case let .real(value):
            return .real(value)
        case let .array(value):
            return .array(value.map { TuistGraph.Plist.Value.from(manifest: $0) })
        case let .dictionary(value):
            return .dictionary(value.mapValues { TuistGraph.Plist.Value.from(manifest: $0) })
        }
    }
}
