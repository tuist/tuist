import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph

extension TuistGraph.Settings {
    /// Maps a ProjectDescription.Settings instance into a TuistGraph.Settings instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of  the settings.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.Settings, generatorPaths: GeneratorPaths) throws -> TuistGraph.Settings {
        let base = manifest.base.mapValues(TuistGraph.SettingValue.from)
        let configurations = try manifest.configurations
            .reduce([TuistGraph.BuildConfiguration: TuistGraph.Configuration?]()) { acc, val in
                var result = acc
                let variant = TuistGraph.BuildConfiguration.from(manifest: val)
                result[variant] = try TuistGraph.Configuration.from(manifest: val, generatorPaths: generatorPaths)
                return result
            }
        let defaultSettings = TuistGraph.DefaultSettings.from(manifest: manifest.defaultSettings)
        return TuistGraph.Settings(
            base: base,
            configurations: configurations,
            defaultSettings: defaultSettings,
            imparted: manifest.imparted.mapValues(TuistGraph.SettingValue.from)
        )
    }
}
