import Foundation
import Path
import XcodeGraph
import XcodeProj

/// A protocol that defines how to map an Xcode project's `XCConfigurationList` into a domain-specific `Settings` model.
///
/// Conforming types provide an asynchronous mapping function that takes a `projectProvider` and an optional
/// `XCConfigurationList`, then returns a `Settings` model. If no configuration list is provided, they return default settings.
protocol SettingsMapping: Sendable {
    /// Maps a given `XCConfigurationList` into a `Settings` model.
    ///
    /// This operation extracts build configurations and their associated build settings, translating them into a
    /// domain-specific `Settings` representation. If the provided configuration list is `nil`, default settings are returned.
    ///
    /// - Parameters:
    ///   - projectProvider: A provider for project-related paths and files, used to resolve paths like `.xcconfig` files.
    ///   - configurationList: The `XCConfigurationList` from which to derive settings. If `nil`, defaults are returned.
    /// - Returns: A `Settings` model derived from the configuration list, or default settings if none are found.
    /// - Throws: If any build settings cannot be properly mapped into a `Settings` model.
    func map(
        xcodeProj: XcodeProj,
        configurationList: XCConfigurationList?
    ) throws -> Settings
}

/// A mapper responsible for converting an Xcode project's configuration list into a `Settings` domain model.
///
/// `SettingsMapper` reads through the project's `XCConfigurationList`, extracting each build configuration along with
/// its raw build settings. It then translates these settings into a structured `Settings` model, associating them with
/// corresponding `BuildConfiguration` variants (e.g., debug or release). Additionally, it attempts to resolve any
/// `.xcconfig` references into absolute paths. If no configuration list is provided, `SettingsMapper` returns default settings.
///
/// Typical usage:
/// ```swift
/// let mapper = SettingsMapper()
/// let settings = try mapper.map(xcodeProj: provider.xcodeProj, configurationList: configurationList)
/// ```
final class XCConfigurationMapper: SettingsMapping {
    func map(
        xcodeProj: XcodeProj,
        configurationList: XCConfigurationList?
    ) throws -> Settings {
        guard let configurationList else {
            return Settings.default
        }

        var configurations: [BuildConfiguration: Configuration?] = [:]
        for buildConfig in configurationList.buildConfigurations {
            let buildSettings = buildConfig.buildSettings
            let settingsDict = try mapBuildSettings(buildSettings)

            var xcconfigAbsolutePath: AbsolutePath?
            if let baseConfigRef = buildConfig.baseConfiguration,
               let xcconfigPath = try baseConfigRef.fullPath(
                   sourceRoot: xcodeProj.srcPathString
               )
            {
                xcconfigAbsolutePath = try AbsolutePath(validating: xcconfigPath)
            }

            let variant = variant(for: buildConfig.name)
            let buildConfiguration = BuildConfiguration(name: buildConfig.name, variant: variant)
            configurations[buildConfiguration] = Configuration(
                settings: settingsDict,
                xcconfig: xcconfigAbsolutePath
            )
        }

        return Settings(
            base: [:],
            baseDebug: [:],
            configurations: configurations,
            defaultSettings: .recommended
        )
    }

    /// Converts a dictionary of raw build settings (`[String: Any]`) into a structured `SettingsDictionary`.
    ///
    /// Each raw setting value is mapped to a `SettingValue`. Strings and arrays of strings are preserved as-is;
    /// other types are converted into strings as a fallback. This ensures that all settings are represented in a
    /// uniform and easily processed manner.
    ///
    /// - Parameter buildSettings: A dictionary of raw build settings.
    /// - Returns: A `SettingsDictionary` containing `SettingValue`-typed settings.
    /// - Throws: If a setting value cannot be mapped (this is typically non-fatal; most values can be stringified).
    func mapBuildSettings(_ buildSettings: [String: BuildSetting]) throws -> SettingsDictionary {
        var settingsDict = SettingsDictionary()
        for (key, value) in buildSettings {
            settingsDict[key] = switch value {
            case let .string(string): .string(string)
            case let .array(array): .array(array)
            }
        }
        return settingsDict
    }

    /// Determines a `BuildConfiguration.Variant` (e.g., `.debug` or `.release`) from a configuration name.
    ///
    /// Uses `ConfigurationMatcher` to infer the variant by analyzing the configuration name for known keywords.
    ///
    /// - Parameter name: The name of the build configuration (e.g., "Debug", "Release", "Development").
    /// - Returns: The corresponding `BuildConfiguration.Variant` inferred from the name.
    private func variant(
        for name: String,
        configurationMatcher: ConfigurationMatching = ConfigurationMatcher()
    ) -> BuildConfiguration.Variant {
        configurationMatcher.variant(for: name)
    }
}
