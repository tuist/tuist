import Basic
import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.Settings: ModelConvertible {
    typealias BuildConfigurationTuple = (TuistCore.BuildConfiguration, TuistCore.Configuration?)
    
    init(manifest: ProjectDescription.Settings, generatorPaths: GeneratorPaths) throws {
        let base = try manifest.base.mapValues { try TuistCore.SettingValue(manifest: $0, generatorPaths: generatorPaths) }
        
        let configurations = try manifest.configurations
            .reduce([TuistCore.BuildConfiguration: TuistCore.Configuration?]()) { acc, val in
                var result = acc
                let variant = try TuistCore.BuildConfiguration(manifest: val, generatorPaths: generatorPaths)
                if let configuration = val.configuration {
                    result[variant] = try TuistCore.Configuration(manifest: configuration, generatorPaths: generatorPaths)
                }
                return result
        }
        let defaultSettings = try TuistCore.DefaultSettings(manifest: manifest.defaultSettings, generatorPaths: generatorPaths)
        self.init(base: base,
                  configurations: configurations,
                  defaultSettings: defaultSettings)
    }
    
    fileprivate static func buildConfigurationTuple(from customConfiguration: CustomConfiguration,
                                                    generatorPaths: GeneratorPaths) throws -> BuildConfigurationTuple {
        let buildConfiguration = try TuistCore.BuildConfiguration(manifest: customConfiguration, generatorPaths: generatorPaths)
        let configuration = try customConfiguration.configuration.flatMap {
            try TuistCore.Configuration(manifest: $0, generatorPaths: generatorPaths)
        }
        return (buildConfiguration, configuration)
    }
}
