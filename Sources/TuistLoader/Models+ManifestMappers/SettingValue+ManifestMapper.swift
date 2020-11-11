import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport

extension TuistCore.SettingValue {
    /// Maps a ProjectDescription.SettingValue instance into a TuistCore.SettingValue model.
    /// - Parameters:
    ///   - manifest: Manifest representation of setting value.
    ///   - pathResolver: Generator paths.
    static func from(manifest: ProjectDescription.SettingValue) -> TuistCore.SettingValue {
        switch manifest {
        case let .string(value):
            return .string(value)
        case let .array(value):
            return .array(value)
        }
    }
}
