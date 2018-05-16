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
    ///   - groups: Project groups.
    ///   - sourceRootPath: path to the folder that contains the generated project.
    ///   - context: generation context.
    ///   - options: generation options.
    /// - Returns: the configuration list reference.
    /// - Throws: an error if the generation fails.
    func generateProjectConfig(project: Project,
                               pbxproj: PBXProj,
                               groups: ProjectGroups,
                               sourceRootPath: AbsolutePath,
                               context: GeneratorContexting,
                               options: GenerationOptions) throws -> PBXObjectReference

    /// Generates the manifests target configuration.
    ///
    /// - Parameters:
    ///   - pbxproj: Xcode project PBXProj object.
    ///   - context: generation context.
    ///   - options: generation options.
    /// - Returns: the configuration list reference.
    /// - Throws: an error if the generation fails.
    func generateManifestsConfig(pbxproj: PBXProj, context: GeneratorContexting, options: GenerationOptions) throws -> PBXObjectReference

    /// Generates the target configuration list and configurations.
    ///
    /// - Parameters:
    ///   - target: target spec.
    ///   - pbxproj: Xcode project PBXProj object.
    ///   - groups: Project groups.
    ///   - sourceRootPath: path to the folder that contains the generated project.
    ///   - context: generation context.
    ///   - options: generation options.
    /// - Returns: the configuration list reference.
    /// - Throws: an error if the generation fails.
    func generateTargetConfig(target: Target,
                              pbxproj: PBXProj,
                              groups: ProjectGroups,
                              sourceRootPath: AbsolutePath,
                              context: GeneratorContexting,
                              options: GenerationOptions) throws -> PBXObjectReference
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
    ///   - groups: Project groups.
    ///   - sourceRootPath: path to the folder that contains the generated project.
    ///   - context: generation context.
    ///   - options: generation options.
    /// - Returns: the confniguration list reference.
    /// - Throws: an error if the generation fails.
    func generateProjectConfig(project: Project,
                               pbxproj: PBXProj,
                               groups: ProjectGroups,
                               sourceRootPath: AbsolutePath,
                               context: GeneratorContexting,
                               options _: GenerationOptions) throws -> PBXObjectReference {
        /// Configuration list
        let configurationList = XCConfigurationList(buildConfigurations: [])
        let configurationListReference = pbxproj.objects.addObject(configurationList)

        try generateProjectSettingsFor(buildConfiguration: .debug,
                                       configuration: project.settings?.debug,
                                       project: project,
                                       groups: groups,
                                       sourceRootPath: sourceRootPath,
                                       context: context,
                                       pbxproj: pbxproj,
                                       configurationList: configurationList)
        try generateProjectSettingsFor(buildConfiguration: .release,
                                       configuration: project.settings?.release,
                                       project: project,
                                       groups: groups,
                                       sourceRootPath: sourceRootPath,
                                       context: context,
                                       pbxproj: pbxproj,
                                       configurationList: configurationList)
        return configurationListReference
    }

    /// Generate the project settings for a given configuration (e.g. Debug or Release)
    ///
    /// - Parameters:
    ///   - buildConfiguration: build configuration (e.g. Debug or Release)
    ///   - configuration: configuration from the project specification.
    ///   - project: projec specification.
    ///   - groups: project groups.
    ///   - sourceRootPath: path that points to the folder where the project is being created.
    ///   - context: generation context.
    ///   - pbxproj: PBXProj object.
    ///   - configurationList: configurations list.
    /// - Throws: an error if the generation fails.
    private func generateProjectSettingsFor(buildConfiguration: BuildConfiguration,
                                            configuration: Configuration?,
                                            project: Project,
                                            groups: ProjectGroups,
                                            sourceRootPath: AbsolutePath,
                                            context: GeneratorContexting,
                                            pbxproj: PBXProj,
                                            configurationList: XCConfigurationList) throws {
        let variant: BuildSettingsProvider.Variant = (buildConfiguration == .debug) ? .debug : .release
        let defaultConfigSettings = BuildSettingsProvider.projectDefault(variant: variant)
        let defaultSettingsAll = BuildSettingsProvider.projectDefault(variant: .all)

        var settings: [String: Any] = [:]
        extend(buildSettings: &settings, with: defaultSettingsAll)
        extend(buildSettings: &settings, with: project.settings?.base ?? [:])
        extend(buildSettings: &settings, with: defaultConfigSettings)

        let variantBuildConfiguration = XCBuildConfiguration(name: buildConfiguration.rawValue.capitalized)
        if let variantConfig = configuration {
            extend(buildSettings: &settings, with: variantConfig.settings)
            if let xcconfig = variantConfig.xcconfig {
                let fileReference = try fileGenerator.generateFile(path: xcconfig,
                                                                   in: groups.projectConfigurations(),
                                                                   sourceRootPath: sourceRootPath,
                                                                   context: context)
                variantBuildConfiguration.baseConfigurationReference = fileReference.reference
            }
        }
        variantBuildConfiguration.buildSettings = settings
        let debugConfigurationReference = pbxproj.objects.addObject(variantBuildConfiguration)
        configurationList.buildConfigurations.append(debugConfigurationReference)
    }

    /// Generates the configuration for the manifests target.
    ///
    /// - Parameters:
    ///   - pbxproj: PBXProj object.
    ///   - context: generation context.
    ///   - options: generation options.
    /// - Returns: the configuration list object reference.
    /// - Throws: an error if the genreation fails.
    func generateManifestsConfig(pbxproj: PBXProj, context: GeneratorContexting, options: GenerationOptions) throws -> PBXObjectReference {
        let configurationList = XCConfigurationList(buildConfigurations: [])
        let configurationListReference = pbxproj.objects.addObject(configurationList)

        let addSettings: (XCBuildConfiguration) throws -> Void = { configuration in
            let frameworkParentDirectory = try context.resourceLocator.projectDescription().parentDirectory
            configuration.buildSettings["FRAMEWORK_SEARCH_PATHS"] = frameworkParentDirectory.asString
            configuration.buildSettings["SWIFT_VERSION"] = Constants.swiftVersion
        }
        if options.buildConfiguration == .debug {
            let debugConfig = XCBuildConfiguration(name: "Debug")
            let debugConfigReference = pbxproj.objects.addObject(debugConfig)
            debugConfig.buildSettings = BuildSettingsProvider.targetDefault(variant: .debug, platform: .macOS, product: .framework, swift: true)
            configurationList.buildConfigurations.append(debugConfigReference)
            try addSettings(debugConfig)
        }
        if options.buildConfiguration == .release {
            let releaseConfig = XCBuildConfiguration(name: "Release")
            let releaseConfigReference = pbxproj.objects.addObject(releaseConfig)
            releaseConfig.buildSettings = BuildSettingsProvider.targetDefault(variant: .release, platform: .macOS, product: .framework, swift: true)
            configurationList.buildConfigurations.append(releaseConfigReference)
            try addSettings(releaseConfig)
        }
        return configurationListReference
    }

    /// Generates the target configuration list and configurations.
    ///
    /// - Parameters:
    ///   - target: target spec.
    ///   - pbxproj: Xcode project PBXProj object.
    ///   - groups: Project groups.
    ///   - sourceRootPath: path to the folder that contains the generated project.
    ///   - context: generation context.
    ///   - options: generation options.
    /// - Returns: the configuration list reference.
    /// - Throws: an error if the generation fails.
    func generateTargetConfig(target _: Target,
                              pbxproj: PBXProj,
                              groups _: ProjectGroups,
                              sourceRootPath _: AbsolutePath,
                              context _: GeneratorContexting,
                              options: GenerationOptions) throws -> PBXObjectReference {
        let configurationList = XCConfigurationList(buildConfigurations: [])
        let configurationListReference = pbxproj.objects.addObject(configurationList)
        // TODO:
        return configurationListReference
    }

    // MARK: - Private

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
