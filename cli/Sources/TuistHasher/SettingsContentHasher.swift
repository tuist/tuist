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
public struct SettingsContentHasher: SettingsContentHashing {
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
        let baseDebugSettingsHash = settings.baseDebug.isEmpty ? nil : try hash(settings.baseDebug)
        let configurationHash = try await hash(settings.configurations)
        let defaultSettingsHash = try hash(settings.defaultSettings)
        return try contentHasher.hash(
            [baseSettingsHash, baseDebugSettingsHash, configurationHash, defaultSettingsHash].compactMap { $0 }
        )
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
            guard !Self.isCompilationCacheSetting(key) else { return nil }
            let filteredValue = filterProductNeutralFlags(from: value)
            return filteredValue.map { (key, $0) }
        }
        let sortedAndNormalizedSettings = filteredSettings
            .sorted(by: { $0.0 < $1.0 })
            .map { "\($0):\($1.normalize())" }.joined(separator: "-")
        return try contentHasher.hash(sortedAndNormalizedSettings)
    }

    /// Build settings that configure Xcode's compilation cache, written by
    /// `XcodeCacheSettingsProjectMapper` into a project's base settings.
    ///
    /// They select where a compilation caches, not what it produces, so two builds
    /// differing only here yield the same binary and must land on the same hash.
    /// Hashing them splits the cache along axes that have nothing to do with the
    /// code: `COMPILATION_CACHE_PLUGIN_PATH` carries the dylib's install path, which
    /// differs between a Homebrew install and a mise one, and toggling
    /// `enableCaching` or the `kura` client flag at all moves every target's hash.
    private static func isCompilationCacheSetting(_ key: String) -> Bool {
        key.hasPrefix("COMPILATION_CACHE_")
    }

    private func filterProductNeutralFlags(from value: SettingValue) -> SettingValue? {
        guard case let .array(elements) = value else {
            return value
        }

        let filteredElements = filterCASPluginOptions(from: filterWarningFlags(from: elements))
        return filteredElements.isEmpty ? nil : .array(filteredElements)
    }

    /// Drops `-cas-plugin-option <value>` pairs, which `XcodeCacheSettingsProjectMapper`
    /// appends to `OTHER_SWIFT_FLAGS` to reach compiler frontends that carry no CLI
    /// environment. They configure the CAS plugin's routing and upload policy, not
    /// codegen. `tuist-upload=false` is the one that matters in practice: the
    /// documented `xcodeCache(upload: Environment.isCI)` policy sets it on developer
    /// machines and not on CI, which would otherwise give the two disjoint cache keys
    /// and deny developers every artifact CI warmed.
    private func filterCASPluginOptions(from elements: [String]) -> [String] {
        var result: [String] = []
        var index = 0

        while index < elements.count {
            if elements[index] == "-cas-plugin-option", index + 1 < elements.count {
                index += 2
                continue
            }

            result.append(elements[index])
            index += 1
        }

        return result
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
