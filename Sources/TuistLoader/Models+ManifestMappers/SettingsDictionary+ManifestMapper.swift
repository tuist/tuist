import Foundation
import ProjectDescription
import TuistGraph

extension TuistGraph.SettingsDictionary {
    /// Maps a ProjectDescription.SettingsDictionary instance into a TuistGraph.SettingsDictionary instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of deployment target model.
    static func from(manifest: ProjectDescription.SettingsDictionary) -> TuistGraph.SettingsDictionary {
        return manifest.mapValues { value in
            switch value {
            case .string(let stringValue):
                return TuistGraph.SettingValue.string(stringValue)
            case .array(let arrayValue):
                return TuistGraph.SettingValue.array(arrayValue)
            }
        }
    }
}
