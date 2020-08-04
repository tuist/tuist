import Foundation
import ProjectDescription
import TSCBasic
import TuistCore

extension TuistCore.Settings {
    typealias BuildConfigurationTuple = (TuistCore.BuildConfiguration, TuistCore.Configuration?)

    /// Maps a ProjectDescription.Settings instance into a TuistCore.Settings instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of  the settings.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.Settings, generatorPaths: GeneratorPaths) throws -> TuistCore.Settings {
        let base = manifest.base.mapValues(TuistCore.SettingValue.from)
        let configurations = try manifest.configurations
            .reduce([TuistCore.BuildConfiguration: TuistCore.Configuration?]()) { acc, val in
                var result = acc
                let variant = TuistCore.BuildConfiguration.from(manifest: val)
                result[variant] = try TuistCore.Configuration.from(manifest: val.configuration, generatorPaths: generatorPaths)
                return result
            }
        let defaultSettings = TuistCore.DefaultSettings.from(manifest: manifest.defaultSettings)
        return TuistCore.Settings(base: base,
                                  configurations: configurations,
                                  defaultSettings: defaultSettings)
    }

    private static func buildConfigurationTuple(from customConfiguration: CustomConfiguration,
                                                path _: AbsolutePath,
                                                generatorPaths: GeneratorPaths) throws -> BuildConfigurationTuple
    {
        let buildConfiguration = TuistCore.BuildConfiguration.from(manifest: customConfiguration)
        let configuration = try customConfiguration.configuration.flatMap {
            try TuistCore.Configuration.from(manifest: $0, generatorPaths: generatorPaths)
        }
        return (buildConfiguration, configuration)
    }
}
