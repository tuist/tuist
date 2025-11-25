import Foundation
import Mockable
import TuistCore
import XcodeGraph

@Mockable
public protocol SettingsContentHashing {
    func hash(settings: Settings) async throws -> String
}

/// `SettingsContentHasher`
/// is responsible for computing a hash that uniquely identifies some `Settings`
public final class SettingsContentHasher: SettingsContentHashing {
    private let contentHasher: ContentHashing
    private let xcconfigHasher: XCConfigContentHashing

    // MARK: - Init

    public init(contentHasher: ContentHashing, xcconfigHasher: XCConfigContentHashing) {
        self.contentHasher = contentHasher
        self.xcconfigHasher = xcconfigHasher
    }

    // MARK: - SettingsContentHashing

    public func hash(settings: Settings) async throws -> String {
        let baseSettingsHash = try hash(settings.base)
        let configurationHash = try await hash(settings.configurations)
        let defaultSettingsHash = try hash(settings.defaultSettings)
        return try contentHasher.hash([baseSettingsHash, configurationHash, defaultSettingsHash])
    }

    private func hash(_ configurations: [BuildConfiguration: Configuration?]) async throws -> String {
        var configurationHashes: [String] = []
        for buildConfiguration in configurations.keys.sorted() {
            var configurationHash = buildConfiguration.name + buildConfiguration.variant.rawValue
            if let configuration = configurations[buildConfiguration] {
                if let configuration {
                    configurationHash += try await hash(configuration)
                }
            }
            configurationHashes.append(configurationHash)
        }
        return try contentHasher.hash(configurationHashes)
    }

    private func hash(_ settingsDictionary: SettingsDictionary) throws -> String {
        let filteredSettings = settingsDictionary.compactMap { key, value -> (String, SettingValue)? in
            let filteredValue = filterWarningFlags(from: value)
            return filteredValue.map { (key, $0) }
        }
        let sortedAndNormalizedSettings = filteredSettings
            .sorted(by: { $0.0 < $1.0 })
            .map { "\($0):\($1.normalize())" }.joined(separator: "-")
        return try contentHasher.hash(sortedAndNormalizedSettings)
    }

    private func filterWarningFlags(from value: SettingValue) -> SettingValue? {
        guard case let .array(elements) = value else {
            return value
        }

        let filteredElements = filterWarningFlags(from: elements)
        return filteredElements.isEmpty ? nil : .array(filteredElements)
    }

    private func filterWarningFlags(from elements: [String]) -> [String] {
        var result: [String] = []
        var index = 0

        while index < elements.count {
            let element = elements[index]

            if element == "-Xfrontend", index + 1 < elements.count {
                let nextElement = elements[index + 1]
                if nextElement.hasPrefix("-warn-") {
                    index += 2
                    continue
                }
            }

            if element.hasPrefix("-Wno-") ||
                element.hasPrefix("-Wunused") ||
                element.hasPrefix("-Wdocumentation") ||
                element.hasPrefix("-Wdeprecated") ||
                element.hasPrefix("-Wimplicit")
            {
                index += 1
                continue
            }

            result.append(element)
            index += 1
        }

        return result
    }

    private func hash(_ configuration: Configuration) async throws -> String {
        var configurationHash = try hash(configuration.settings)
        if let xcconfigPath = configuration.xcconfig {
            let xcconfigHash = try await xcconfigHasher.hash(path: xcconfigPath)
            configurationHash += xcconfigHash
        }
        return configurationHash
    }

    private func hash(_ defaultSettings: DefaultSettings) throws -> String {
        var defaultSettingHash: String
        switch defaultSettings {
        case let .recommended(excludedKeys):
            defaultSettingHash = "recommended"
            let excludedKeysHash = try contentHasher.hash(excludedKeys.sorted())
            defaultSettingHash += excludedKeysHash
        case let .essential(excludedKeys):
            defaultSettingHash = "essential"
            let excludedKeysHash = try contentHasher.hash(excludedKeys.sorted())
            defaultSettingHash += excludedKeysHash
        case .none:
            defaultSettingHash = "none"
        }
        return defaultSettingHash
    }
}
