import Foundation
import ProjectDescription
import TuistCore
import XcodeGraph

extension XcodeGraph.Settings {
    /// Maps a ProjectDescription.Settings instance into a XcodeGraph.Settings instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of  the settings.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.Settings, generatorPaths: GeneratorPaths) throws -> XcodeGraph.Settings {
        let base = manifest.base.mapValues(XcodeGraph.SettingValue.from)
        let configurations = try manifest.configurations
            .reduce([XcodeGraph.BuildConfiguration: XcodeGraph.Configuration?]()) { acc, val in
                var result = acc
                let variant = XcodeGraph.BuildConfiguration.from(manifest: val)
                result[variant] = try XcodeGraph.Configuration.from(manifest: val, generatorPaths: generatorPaths)
                return result
            }
        let defaultSettings = XcodeGraph.DefaultSettings.from(manifest: manifest.defaultSettings)
        return XcodeGraph.Settings(
            base: base,
            configurations: configurations,
            defaultSettings: defaultSettings,
            defaultConfiguration: manifest.defaultConfiguration
        )
    }
}
