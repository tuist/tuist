import Foundation
import Path
import XcodeGraph
import XcodeProj

extension PBXTarget {
    /// Retrieves the path to the Info.plist file from the target's build settings.
    ///
    /// - Returns: The `INFOPLIST_FILE` value if present, otherwise `nil`.
    func infoPlistPaths() -> [BuildConfiguration: String] {
        buildConfigurationList?.stringSettings(for: .infoPlistFile) ?? [:]
    }

    /// Retrieves the path to the entitlements file from the target's build settings.
    ///
    /// - Returns: The `CODE_SIGN_ENTITLEMENTS` value if present, otherwise `nil`.
    func entitlementsPath() -> [BuildConfiguration: String] {
        buildConfigurationList?.stringSettings(for: .codeSignEntitlements) ?? [:]
    }

    func defaultBuildConfiguration(
        configurationMatcher: ConfigurationMatching = ConfigurationMatcher()
    ) -> BuildConfiguration? {
        guard let defaultName = buildConfigurationList?.defaultConfigurationName else { return nil }
        let variant = configurationMatcher.variant(for: defaultName)
        return BuildConfiguration(name: defaultName, variant: variant)
    }

    /// Retrieves deployment target versions for various platforms supported by this target.
    ///
    /// Checks build configurations for:
    /// - `IPHONEOS_DEPLOYMENT_TARGET`
    /// - `MACOSX_DEPLOYMENT_TARGET`
    /// - `WATCHOS_DEPLOYMENT_TARGET`
    /// - `TVOS_DEPLOYMENT_TARGET`
    /// - `VISIONOS_DEPLOYMENT_TARGET`
    ///
    /// - Returns: A `DeploymentTargets` instance containing any discovered versions.
    func deploymentTargets() -> DeploymentTargets {
        guard let configList = buildConfigurationList else {
            return DeploymentTargets(iOS: nil, macOS: nil, watchOS: nil, tvOS: nil, visionOS: nil)
        }

        let keys: [BuildSettingKey] = [
            .iPhoneOSDeploymentTarget,
            .macOSDeploymentTarget,
            .watchOSDeploymentTarget,
            .tvOSDeploymentTarget,
            .visionOSDeploymentTarget,
        ]

        let targets = configList.allDeploymentTargets(keys: keys)
        return DeploymentTargets(
            iOS: targets[.iPhoneOSDeploymentTarget],
            macOS: targets[.macOSDeploymentTarget],
            watchOS: targets[.watchOSDeploymentTarget],
            tvOS: targets[.tvOSDeploymentTarget],
            visionOS: targets[.visionOSDeploymentTarget]
        )
    }

    /// Returns the build settings from the "Debug" build configuration, or an empty dictionary if not present.
    var debugBuildSettings: [String: BuildSetting] {
        buildConfigurationList?.buildConfigurations.first(where: { $0.name == "Debug" })?.buildSettings
            ?? [:]
    }
}
