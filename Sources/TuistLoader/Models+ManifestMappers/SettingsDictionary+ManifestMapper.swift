import Foundation
import ProjectDescription
import XcodeGraph

extension XcodeGraph.SettingsDictionary {
    /// Maps a ProjectDescription.SettingsDictionary instance into a XcodeGraph.SettingsDictionary instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of deployment target model.
    static func from(manifest: ProjectDescription.SettingsDictionary) -> XcodeGraph.SettingsDictionary {
        manifest.mapValues { value in
            switch value {
            case let .string(stringValue):
                return XcodeGraph.SettingValue.string(stringValue)
            case let .array(arrayValue):
                return XcodeGraph.SettingValue.array(arrayValue)
            }
        }
    }
}
