import Foundation
import TuistCore

public protocol SettingsContentHashing {
    func hash(settings: Settings) throws -> String
}

/// `SettingsContentHasher`
/// is responsible for computing a hash that uniquely identifies some `Settings`
public final class SettingsContentHasher: SettingsContentHashing {
    private let contentHasher: ContentHashing

    // MARK: - Init

    public init(contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
    }

    // MARK: - InfoPlistContentHashing

    public func hash(settings: Settings) throws -> String {
        let baseSettingsHash = hash(settings.base)
        let configurationHash = try hash(settings.configurations)
        let defaultSettingsHash = settings.defaultSettings.rawValue
        return try contentHasher.hash([baseSettingsHash, configurationHash, defaultSettingsHash])
    }

    private func hash(_ configurations: [BuildConfiguration: Configuration?]) throws -> String {
        var configurationHashes: [String] = []
        for buildConfiguration in configurations.keys.sorted() {
            var configurationHash = buildConfiguration.name + buildConfiguration.variant.rawValue
            if let configuration = configurations[buildConfiguration] {
                if let configuration = configuration {
                    configurationHash += try hash(configuration)
                }
            }
            configurationHashes.append(configurationHash)
        }
        return try contentHasher.hash(configurationHashes)
    }

    private func hash(_ settingsDictionary: SettingsDictionary) -> String {
        settingsDictionary.map { "\($0):\($1.normalize())" }.joined(separator: "-")
    }

    private func hash(_ configuration: Configuration) throws -> String {
        var configurationHash = hash(configuration.settings)
        if let xcconfigPath = configuration.xcconfig {
            let xcconfigHash = try contentHasher.hash(fileAtPath: xcconfigPath)
            configurationHash += xcconfigHash
        }
        return configurationHash
    }
}
