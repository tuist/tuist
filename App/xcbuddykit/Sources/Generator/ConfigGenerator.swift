import Foundation
import xcodeproj

/// Project generation protocol.
protocol ConfigGenerating: AnyObject {
    /// Generates the project configuration list and configurations.
    ///
    /// - Parameters:
    ///   - project: project spec.
    ///   - pbxproj: Xcode project PBXProj object.
    ///   - context: generation context.
    /// - Returns: the confniguration list reference.
    /// - Throws: an error if the generation fails.
    func generateProjectConfig(project: Project, pbxproj: PBXProj, context: GeneratorContexting) throws -> PBXObjectReference
}

/// Config generator.
final class ConfigGenerator: ConfigGenerating {
    /// Generates the project configuration list and configurations.
    ///
    /// - Parameters:
    ///   - project: project spec.
    ///   - pbxproj: Xcode project PBXProj object.
    ///   - context: generation context.
    /// - Returns: the confniguration list reference.
    /// - Throws: an error if the generation fails.
    func generateProjectConfig(project: Project, pbxproj: PBXProj, context _: GeneratorContexting) throws -> PBXObjectReference {
        /// Default build settings
        let defaultAll = BuildSettingsProvider.projectDefault(variant: .all)
        let defaultDebug = BuildSettingsProvider.projectDefault(variant: .debug)
        let defaultRelease = BuildSettingsProvider.projectDefault(variant: .release)

        // Debug
        var debugSettings: [String: Any] = [:]
        extend(buildSettings: &debugSettings, with: defaultAll)
        extend(buildSettings: &debugSettings, with: defaultDebug)
        if let debugConfig = project.settings?.debug {
            extend(buildSettings: &debugSettings, with: debugConfig.settings)
        }
        let debugConfiguration = XCBuildConfiguration(name: "Debug")
        debugConfiguration.buildSettings = debugSettings
        let debugConfigurationReference = pbxproj.objects.addObject(debugConfiguration)

        // Release
        var releaseSettings: [String: Any] = [:]
        extend(buildSettings: &releaseSettings, with: defaultAll)
        extend(buildSettings: &releaseSettings, with: defaultRelease)
        if let releaseConfig = project.settings?.release {
            extend(buildSettings: &releaseSettings, with: releaseConfig.settings)
        }
        let releaseConfiguration = XCBuildConfiguration(name: "Release")
        releaseConfiguration.buildSettings = releaseSettings
        let releaseConfigurationReference = pbxproj.objects.addObject(releaseConfiguration)

        /// Configuration list
        let configurationList = XCConfigurationList(buildConfigurations: [])
        let configurationListReference = pbxproj.objects.addObject(configurationList)
        configurationList.buildConfigurations.append(debugConfigurationReference)
        configurationList.buildConfigurations.append(releaseConfigurationReference)
        return configurationListReference
    }

    /// Extends build settings with other build settings.
    ///
    /// - Parameters:
    ///   - settings: build settings to be extended.
    ///   - other: build settings to be extended with.
    fileprivate func extend(buildSettings: inout [String: Any], with other: [String: Any]) {
        other.forEach { buildSettings[$0.key] = $0.value }
    }
}
