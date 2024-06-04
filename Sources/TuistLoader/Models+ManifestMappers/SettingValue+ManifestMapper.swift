import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import XcodeProjectGenerator
import TuistSupport

extension XcodeProjectGenerator.SettingValue {
    /// Maps a ProjectDescription.SettingValue instance into a XcodeProjectGenerator.SettingValue model.
    /// - Parameters:
    ///   - manifest: Manifest representation of setting value.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.SettingValue) -> XcodeProjectGenerator.SettingValue {
        switch manifest {
        case let .string(value):
            return .string(value)
        case let .array(value):
            return .array(value)
        }
    }
}
