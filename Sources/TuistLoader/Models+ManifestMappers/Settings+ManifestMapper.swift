import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import XcodeProjectGenerator

extension XcodeProjectGenerator.Settings {
    /// Maps a ProjectDescription.Settings instance into a XcodeProjectGenerator.Settings instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of  the settings.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.Settings, generatorPaths: GeneratorPaths) throws -> XcodeProjectGenerator.Settings {
        let base = manifest.base.mapValues(XcodeProjectGenerator.SettingValue.from)
        let configurations = try manifest.configurations
            .reduce([XcodeProjectGenerator.BuildConfiguration: XcodeProjectGenerator.Configuration?]()) { acc, val in
                var result = acc
                let variant = XcodeProjectGenerator.BuildConfiguration.from(manifest: val)
                result[variant] = try XcodeProjectGenerator.Configuration.from(manifest: val, generatorPaths: generatorPaths)
                return result
            }
        let defaultSettings = XcodeProjectGenerator.DefaultSettings.from(manifest: manifest.defaultSettings)
        return XcodeProjectGenerator.Settings(
            base: base,
            configurations: configurations,
            defaultSettings: defaultSettings
        )
    }
}
