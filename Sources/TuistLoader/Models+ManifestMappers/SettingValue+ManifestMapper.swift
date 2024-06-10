import Foundation
import Path
import ProjectDescription
import TuistCore
import TuistSupport
import XcodeGraph

extension XcodeGraph.SettingValue {
    /// Maps a ProjectDescription.SettingValue instance into a XcodeGraph.SettingValue model.
    /// - Parameters:
    ///   - manifest: Manifest representation of setting value.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.SettingValue) -> XcodeGraph.SettingValue {
        switch manifest {
        case let .string(value):
            return .string(value)
        case let .array(value):
            return .array(value)
        }
    }
}
