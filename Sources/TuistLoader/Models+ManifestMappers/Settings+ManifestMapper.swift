import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph

extension TuistGraph.Settings {
    typealias BuildConfigurationTuple = (TuistGraph.BuildConfiguration, TuistGraph.Configuration?)

    /// Maps a ProjectDescription.Settings instance into a TuistCore.Settings instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of  the settings.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.Settings, generatorPaths: GeneratorPaths) throws -> TuistGraph.Settings {
        let base = manifest.base.mapValues(TuistGraph.SettingValue.from)
        let configurations = try manifest.configurations
            .reduce([TuistGraph.BuildConfiguration: TuistGraph.Configuration?]()) { acc, val in
                var result = acc
                let variant = TuistGraph.BuildConfiguration.from(manifest: val)
                result[variant] = try TuistGraph.Configuration.from(manifest: val.configuration, generatorPaths: generatorPaths)
                return result
            }
        let defaultSettings = TuistGraph.DefaultSettings.from(manifest: manifest.defaultSettings)
        return TuistGraph.Settings(base: base,
                                   configurations: configurations,
                                   defaultSettings: defaultSettings)
    }

    private static func buildConfigurationTuple(from customConfiguration: CustomConfiguration,
                                                path _: AbsolutePath,
                                                generatorPaths: GeneratorPaths) throws -> BuildConfigurationTuple
    {
        let buildConfiguration = TuistGraph.BuildConfiguration.from(manifest: customConfiguration)
        let configuration = try customConfiguration.configuration.flatMap {
            try TuistGraph.Configuration.from(manifest: $0, generatorPaths: generatorPaths)
        }
        return (buildConfiguration, configuration)
    }
}
