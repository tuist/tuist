import Basic
import Foundation
import xcodeproj

/// Project generation protocol.
protocol ConfigGenerating: AnyObject {
    /// Generates the project configuration list and configurations.
    ///
    /// - Parameters:
    ///   - project: Project specification.
    ///   - objects: Xcode project objects.
    ///   - fileElements: Xcode project file elements.
    ///   - options: Generation objects.
    /// - Returns: configuration list object reference.
    func generateProjectConfig(project: Project,
                               objects: PBXObjects,
                               fileElements: ProjectFileElements,
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

    /// Generates the target configuration.
    ///
    /// - Parameters:
    ///   - target: target specification.
    ///   - pbxTarget: Xcode project target.
    ///   - objects: Xcode project objects.
    ///   - fileElements: Xcode project file elements.
    ///   - options: generation options.
    ///   - sourceRootPath: path to the folder where the Xcode project is generated.
    func generateTargetConfig(_ target: Target,
                              pbxTarget: PBXTarget,
                              objects: PBXObjects,
                              fileElements: ProjectFileElements,
                              options: GenerationOptions,
                              sourceRootPath: AbsolutePath) throws
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
    ///   - project: Project specification.
    ///   - objects: Xcode project objects.
    ///   - fileElements: Xcode project file elements.
    ///   - options: Generation objects.
    /// - Returns: configuration list object reference.
    func generateProjectConfig(project: Project,
                               objects: PBXObjects,
                               fileElements: ProjectFileElements,
                               options: GenerationOptions) throws -> PBXObjectReference {
        /// Configuration list
        let configurationList = XCConfigurationList(buildConfigurationsReferences: [])
        let configurationListReference = objects.addObject(configurationList)

        if options.buildConfiguration == .debug {
            try generateProjectSettingsFor(buildConfiguration: .debug,
                                           configuration: project.settings?.debug,
                                           project: project,
                                           fileElements: fileElements,
                                           objects: objects,
                                           configurationList: configurationList)
        }

        if options.buildConfiguration == .release {
            try generateProjectSettingsFor(buildConfiguration: .release,
                                           configuration: project.settings?.release,
                                           project: project,
                                           fileElements: fileElements,
                                           objects: objects,
                                           configurationList: configurationList)
        }
        return configurationListReference
    }

    /// Generate the project settings for a given configuration (e.g. Debug or Release)
    ///
    /// - Parameters:
    ///   - buildConfiguration: build configuration (e.g. Debug or Release)
    ///   - configuration: configuration from the project specification.
    ///   - project: project specification.
    ///   - fileElements: project file elements.
    ///   - objects: Xcode project objects.
    ///   - configurationList: configurations list.
    /// - Throws: an error if the generation fails.
    private func generateProjectSettingsFor(buildConfiguration: BuildConfiguration,
                                            configuration: Configuration?,
                                            project: Project,
                                            fileElements: ProjectFileElements,
                                            objects: PBXObjects,
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
                let fileReference = fileElements.file(path: xcconfig)
                variantBuildConfiguration.baseConfigurationReference = fileReference?.reference
            }
        }
        variantBuildConfiguration.buildSettings = settings
        let debugConfigurationReference = objects.addObject(variantBuildConfiguration)
        configurationList.buildConfigurationsReferences.append(debugConfigurationReference)
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
        let configurationList = XCConfigurationList(buildConfigurationsReferences: [])
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
            configurationList.buildConfigurationsReferences.append(debugConfigReference)
            try addSettings(debugConfig)
        }
        if options.buildConfiguration == .release {
            let releaseConfig = XCBuildConfiguration(name: "Release")
            let releaseConfigReference = pbxproj.objects.addObject(releaseConfig)
            releaseConfig.buildSettings = BuildSettingsProvider.targetDefault(variant: .release, platform: .macOS, product: .framework, swift: true)
            configurationList.buildConfigurationsReferences.append(releaseConfigReference)
            try addSettings(releaseConfig)
        }
        return configurationListReference
    }

    /// Generates the target configuration.
    ///
    /// - Parameters:
    ///   - target: target specification.
    ///   - pbxTarget: Xcode project target.
    ///   - objects: Xcode project objects.
    ///   - fileElements: Xcode project file elements.
    ///   - options: generation options.
    ///   - sourceRootPath: path to the folder where the Xcode project is generated.
    func generateTargetConfig(_ target: Target,
                              pbxTarget: PBXTarget,
                              objects: PBXObjects,
                              fileElements: ProjectFileElements,
                              options: GenerationOptions,
                              sourceRootPath: AbsolutePath) throws {
        let configurationList = XCConfigurationList(buildConfigurationsReferences: [])
        let configurationListReference = objects.addObject(configurationList)
        pbxTarget.buildConfigurationListReference = configurationListReference

        if options.buildConfiguration == .debug {
            try generateTargetSettingsFor(target: target,
                                          buildConfiguration: .debug,
                                          configuration: target.settings?.debug,
                                          fileElements: fileElements,
                                          objects: objects,
                                          configurationList: configurationList,
                                          sourceRootPath: sourceRootPath)
        }

        if options.buildConfiguration == .release {
            try generateTargetSettingsFor(target: target,
                                          buildConfiguration: .release,
                                          configuration: target.settings?.release,
                                          fileElements: fileElements,
                                          objects: objects,
                                          configurationList: configurationList,
                                          sourceRootPath: sourceRootPath)
        }
    }

    /// Generates the target settings.
    ///
    /// - Parameters:
    ///   - target: target specification.
    ///   - buildConfiguration: build configuration to be generated.
    ///   - configuration: target configuration.
    ///   - fileElements: Xcode project file elements.
    ///   - objects: Xcode project objects.
    ///   - configurationList: target configuration list.
    ///   - sourceRootPath: path to the folder where the Xcode project is generated.
    private func generateTargetSettingsFor(target: Target,
                                           buildConfiguration: BuildConfiguration,
                                           configuration: Configuration?,
                                           fileElements: ProjectFileElements,
                                           objects: PBXObjects,
                                           configurationList: XCConfigurationList,
                                           sourceRootPath: AbsolutePath) throws {
        let product = settingsProviderProduct(target)
        let platform = settingsProviderPlatform(target)

        let defaultConfigSettings = BuildSettingsProvider.targetDefault(platform: platform, product: product)

        var settings: [String: Any] = [:]
        extend(buildSettings: &settings, with: defaultConfigSettings)
        extend(buildSettings: &settings, with: target.settings?.base ?? [:])
        extend(buildSettings: &settings, with: configuration?.settings ?? [:])

        let variantBuildConfiguration = XCBuildConfiguration(name: buildConfiguration.rawValue.capitalized)
        if let variantConfig = configuration {
            if let xcconfig = variantConfig.xcconfig {
                let fileReference = fileElements.file(path: xcconfig)
                variantBuildConfiguration.baseConfigurationReference = fileReference?.reference
            }
        }

        /// Target attributes
        settings["PRODUCT_BUNDLE_IDENTIFIER"] = target.bundleId
        settings["INFOPLIST_FILE"] = "$(SRCROOT)/\(target.infoPlist.relative(to: sourceRootPath).asString)"
        if let entitlements = target.entitlements {
            settings["CODE_SIGN_ENTITLEMENTS"] = "$(SRCROOT)/\(entitlements.relative(to: sourceRootPath).asString)"
        }
        settings["SDKROOT"] = target.platform.xcodeSdkRoot
        settings["SUPPORTED_PLATFORMS"] = target.platform.xcodeSupportedPlatforms
        // TODO: We should show a warning here
        if settings["SWIFT_VERSION"] == nil {
            settings["SWIFT_VERSION"] = Constants.swiftVersion
        }

        variantBuildConfiguration.buildSettings = settings
        let debugConfigurationReference = objects.addObject(variantBuildConfiguration)
        configurationList.buildConfigurationsReferences.append(debugConfigurationReference)
    }

    /// It returns the build settings provider platform from a given target.
    ///
    /// - Parameter target: target specification.
    /// - Returns: platform.
    fileprivate func settingsProviderPlatform(_ target: Target) -> BuildSettingsProvider.Platform? {
        var platform: BuildSettingsProvider.Platform?
        switch target.platform {
        case .iOS: platform = .iOS
        case .macOS: platform = .macOS
        case .tvOS: platform = .tvOS
        case .watchOS: platform = .watchOS
        }
        return platform
    }

    /// It returns the build settings provider product from a given target.
    ///
    /// - Parameter target: target specification.
    /// - Returns: product type.
    fileprivate func settingsProviderProduct(_ target: Target) -> BuildSettingsProvider.Product? {
        switch target.product {
        case .app:
            return .application
        case .dynamicLibrary:
            return .dynamicLibrary
        case .staticLibrary:
            return .staticLibrary
        case .framework:
            return .framework
        default:
            return nil
        }
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
