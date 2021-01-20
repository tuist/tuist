import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport
import TuistGraph

extension TuistGraph.SettingValue {
    /// Maps a ProjectDescription.SettingValue instance into a TuistCore.SettingValue model.
    /// - Parameters:
    ///   - manifest: Manifest representation of setting value.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.SettingValue) -> TuistGraph.SettingValue {
        switch manifest {
        case let .string(value):
            return .string(value)
        case let .array(value):
            return .array(value)
        }
    }
}
