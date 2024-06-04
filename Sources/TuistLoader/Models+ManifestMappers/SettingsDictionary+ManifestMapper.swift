import Foundation
import ProjectDescription
import XcodeProjectGenerator

extension XcodeProjectGenerator.SettingsDictionary {
    /// Maps a ProjectDescription.SettingsDictionary instance into a XcodeProjectGenerator.SettingsDictionary instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of deployment target model.
    static func from(manifest: ProjectDescription.SettingsDictionary) -> XcodeProjectGenerator.SettingsDictionary {
        manifest.mapValues { value in
            switch value {
            case let .string(stringValue):
                return XcodeProjectGenerator.SettingValue.string(stringValue)
            case let .array(arrayValue):
                return XcodeProjectGenerator.SettingValue.array(arrayValue)
            }
        }
    }
}
