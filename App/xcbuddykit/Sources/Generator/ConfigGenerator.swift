import Basic
import Foundation
import xcodeproj

/// Project generation protocol.
protocol ConfigGenerating: AnyObject {
    /// Generates the project configuration list and configurations.
    ///
    /// - Parameters:
    ///   - project: project spec.
    ///   - pbxproj: Xcode project PBXProj object.
    ///   - mainGroup: Xcode project main group.
    ///   - sourceRootPath: path to the folder that contains the generated project.
    ///   - context: generation context.
    /// - Returns: the confniguration list reference.
    /// - Throws: an error if the generation fails.
    func generateProjectConfig(project: Project,
                               pbxproj: PBXProj,
                               mainGroup: PBXGroup,
                               sourceRootPath: AbsolutePath,
                               context: GeneratorContexting) throws -> PBXObjectReference

    func generateManifestsConfig(pbxproj: PBXProj, context: GeneratorContexting) throws -> PBXObjectReference
}

/// Config generator.
final class ConfigGenerator: ConfigGenerating {
    /// File generator.
    let fileGenerator: FileGenerating

    /// Default config generator constructor.
    ///
    /// - Parameter fileGenerator: generator used to generate files.
    init(fileGenerator: FileGenerating = FileGenerator()) {
        self.fileGenerator = fileGenerator
    }

    /// Generates the project configuration list and configurations.
    ///
    /// - Parameters:
    ///   - project: project spec.
    ///   - pbxproj: Xcode project PBXProj object.
    ///   - mainGroup: Xcode project main group.
    ///   - sourceRootPath: path to the folder that contains the generated project.
    ///   - context: generation context.
    /// - Returns: the confniguration list reference.
    /// - Throws: an error if the generation fails.
    func generateProjectConfig(project: Project,
                               pbxproj: PBXProj,
                               mainGroup: PBXGroup,
                               sourceRootPath: AbsolutePath,
                               context: GeneratorContexting) throws -> PBXObjectReference {
        /// Configurations group
        let configsGroup = PBXGroup(children: [], sourceTree: .group, name: "Configurations")
        let configsGroupReference = pbxproj.objects.addObject(configsGroup)
        mainGroup.children.append(configsGroupReference)

        /// Default build settings
        let defaultAll = BuildSettingsProvider.projectDefault(variant: .all)
        let defaultDebug = BuildSettingsProvider.projectDefault(variant: .debug)
        let defaultRelease = BuildSettingsProvider.projectDefault(variant: .release)

        // Debug
        var debugSettings: [String: Any] = [:]
        extend(buildSettings: &debugSettings, with: defaultAll)
        extend(buildSettings: &debugSettings, with: project.settings?.base ?? [:])
        extend(buildSettings: &debugSettings, with: defaultDebug)
        let debugConfiguration = XCBuildConfiguration(name: "Debug")
        if let debugConfig = project.settings?.debug {
            extend(buildSettings: &debugSettings, with: debugConfig.settings)
            if let xcconfigDebug = debugConfig.xcconfig {
                let fileReference = try fileGenerator.generateFile(path: xcconfigDebug,
                                                                   in: configsGroup,
                                                                   sourceRootPath: sourceRootPath,
                                                                   context: context)
                debugConfiguration.baseConfigurationReference = fileReference.reference
            }
        }
        debugConfiguration.buildSettings = debugSettings
        let debugConfigurationReference = pbxproj.objects.addObject(debugConfiguration)

        // Release
        var releaseSettings: [String: Any] = [:]
        extend(buildSettings: &releaseSettings, with: defaultAll)
        extend(buildSettings: &debugSettings, with: project.settings?.base ?? [:])
        extend(buildSettings: &releaseSettings, with: defaultRelease)
        let releaseConfiguration = XCBuildConfiguration(name: "Release")
        if let releaseConfig = project.settings?.release {
            extend(buildSettings: &releaseSettings, with: releaseConfig.settings)
            if let xcconfigRelease = releaseConfig.xcconfig {
                let fileReference = try fileGenerator.generateFile(path: xcconfigRelease,
                                                                   in: configsGroup,
                                                                   sourceRootPath: sourceRootPath,
                                                                   context: context)
                releaseConfiguration.baseConfigurationReference = fileReference.reference
            }
        }
        releaseConfiguration.buildSettings = releaseSettings
        let releaseConfigurationReference = pbxproj.objects.addObject(releaseConfiguration)

        /// Configuration list
        let configurationList = XCConfigurationList(buildConfigurations: [])
        let configurationListReference = pbxproj.objects.addObject(configurationList)
        configurationList.buildConfigurations.append(debugConfigurationReference)
        configurationList.buildConfigurations.append(releaseConfigurationReference)
        return configurationListReference
    }

    func generateManifestsConfig(pbxproj: PBXProj, context: GeneratorContexting) throws -> PBXObjectReference {
        let configurationList = XCConfigurationList(buildConfigurations: [])
        let debugConfig = XCBuildConfiguration(name: "Debug")
        let debugConfigReference = pbxproj.objects.addObject(debugConfig)
        debugConfig.buildSettings = BuildSettingsProvider.targetDefault(variant: .debug, platform: .macOS, product: .framework, swift: true)
        let releaseConfig = XCBuildConfiguration(name: "Release")
        let releaseConfigReference = pbxproj.objects.addObject(releaseConfig)
        releaseConfig.buildSettings = BuildSettingsProvider.targetDefault(variant: .release, platform: .macOS, product: .framework, swift: true)
        configurationList.buildConfigurations.append(debugConfigReference)
        configurationList.buildConfigurations.append(releaseConfigReference)
        let configurationListReference = pbxproj.objects.addObject(configurationList)

        let addSettings: (XCBuildConfiguration) throws -> Void = { configuration in
            let frameworkParentDirectory = try context.resourceLocator.projectDescription().parentDirectory
            configuration.buildSettings["FRAMEWORK_SEARCH_PATHS"] = frameworkParentDirectory.asString
            configuration.buildSettings["SWIFT_VERSION"] = Constants.swiftVersion
        }
        try addSettings(debugConfig)
        try addSettings(releaseConfig)
        return configurationListReference
    }

    /// Extends build settings with other build settings.
    ///
    /// - Parameters:
    ///   - settings: build settings to be extended.
    ///   - other: build settings to be extended with.
    fileprivate func extend(buildSettings: inout [String: Any], with other: [String: Any]) {
        other.forEach { key, value in
            if buildSettings[key] == nil {
                buildSettings[key] = value
            } else {
                let previousValue: Any = buildSettings[key]!
                if let previousValueString = previousValue as? String, let newValueString = value as? String {
                    buildSettings[key] = "\(previousValueString) \(newValueString)"
                } else {
                    buildSettings[key] = value
                }
            }
        }
    }
}
