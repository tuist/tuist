import Foundation
import ProjectDescription
import TuistGraph

extension TuistGraph.SettingsDictionary {
    /// Maps a ProjectDescription.SettingsDictionary instance into a TuistGraph.SettingsDictionary instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of deployment target model.
    static func from(manifest: ProjectDescription.SettingsDictionary) -> TuistGraph.SettingsDictionary {
        manifest.mapValues { value in
            switch value {
            case let .string(stringValue):
                return TuistGraph.SettingValue.string(stringValue)
            case let .array(arrayValue):
                return TuistGraph.SettingValue.array(arrayValue)
            }
        }
    }
}
