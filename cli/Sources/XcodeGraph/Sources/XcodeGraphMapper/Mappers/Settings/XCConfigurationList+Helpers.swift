import XcodeGraph
import XcodeProj

extension XCConfigurationList {
    /// Retrieves a build setting value from the first configuration in which it is found.
    ///
    /// - Parameter key: The `BuildSettingKey` to look up.
    /// - Returns: The value as a `String` if found, otherwise `nil`.
    func stringSettings(for key: BuildSettingKey) -> [BuildConfiguration: String] {
        let configurationMatcher = ConfigurationMatcher()
        var results = [BuildConfiguration: String]()
        for config in buildConfigurations {
            if let value = config.buildSettings[key]?.stringValue {
                let variant = configurationMatcher.variant(for: config.name)
                let buildConfig = BuildConfiguration(name: config.name, variant: variant)
                results[buildConfig] = value
            }
        }
        return results
    }

    /// Retrieves all deployment target values from all configurations and aggregates them.
    ///
    /// - Parameters:
    ///   - keys: A list of keys to search (e.g., `.iPhoneOSDeploymentTarget`, `.macOSDeploymentTarget`)
    /// - Returns: A dictionary mapping `BuildSettingKey` to the found value.
    func allDeploymentTargets(keys: [BuildSettingKey]) -> [BuildSettingKey: String] {
        var results = [BuildSettingKey: String]()

        for key in keys {
            for config in buildConfigurations {
                if let value = config.buildSettings[key]?.stringValue {
                    results[key] = value
                    break // Once found, move to the next key
                }
            }
        }

        return results
    }
}
