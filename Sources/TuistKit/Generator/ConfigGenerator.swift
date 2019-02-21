import Basic
import Foundation
import TuistCore
import xcodeproj

protocol ConfigGenerating: AnyObject {
    
    func generateProjectConfig(
        project: Project,
        pbxproj: PBXProj,
        fileElements: ProjectFileElements,
        configurations: ConfigurationList,
        isRoot: Bool,
        options: GenerationOptions
    ) throws -> XCConfigurationList
    
    func generateManifestsConfig(
        pbxproj: PBXProj,
        options: GenerationOptions,
        resourceLocator: ResourceLocating,
        configurations: ConfigurationList
    ) throws -> XCConfigurationList

    func generateTargetConfig(
        _ target: Target,
        pbxTarget: PBXTarget,
        pbxproj: PBXProj,
        fileElements: ProjectFileElements,
        configurations: ConfigurationList,
        options: GenerationOptions,
        sourceRootPath: AbsolutePath
    ) throws
}

final class ConfigGenerator: ConfigGenerating {
    // MARK: - Attributes

    let fileGenerator: FileGenerating

    // MARK: - Init

    init(fileGenerator: FileGenerating = FileGenerator()) {
        self.fileGenerator = fileGenerator
    }

    func generateProjectConfig(
        project: Project,
        pbxproj: PBXProj,
        fileElements: ProjectFileElements,
        configurations: ConfigurationList,
        isRoot: Bool,
        options _: GenerationOptions
    ) throws -> XCConfigurationList {
        /// Configuration list
        let configurationList = XCConfigurationList(buildConfigurations: [ ])
        
        pbxproj.add(object: configurationList)
        
        for configuration in configurations {
            
            try generateProjectSettingsFor(
                buildConfiguration: configuration.buildConfiguration,
                configuration: configuration,
                project: project,
                fileElements: fileElements,
                pbxproj: pbxproj,
                configurationList: configurationList,
                isRoot: isRoot
            )
            
        }

        return configurationList
    }

    func generateTargetConfig(
        _ target: Target,
        pbxTarget: PBXTarget,
        pbxproj: PBXProj,
        fileElements: ProjectFileElements,
        configurations: ConfigurationList,
        options _: GenerationOptions,
        sourceRootPath: AbsolutePath
    ) throws {
        
        let configurationList = XCConfigurationList(buildConfigurations: [ ])
        
        pbxproj.add(object: configurationList)
        pbxTarget.buildConfigurationList = configurationList
        
        for configuration in configurations {
            
            try generateTargetSettingsFor(
                target: target,
                buildConfiguration: configuration.buildConfiguration,
                configuration: configuration,
                fileElements: fileElements,
                pbxproj: pbxproj,
                configurationList: configurationList,
                sourceRootPath: sourceRootPath
            )
            
        }

    }

    func generateManifestsConfig(
        pbxproj: PBXProj,
        options _: GenerationOptions,
        resourceLocator: ResourceLocating = ResourceLocator(),
        configurations: ConfigurationList
    ) throws -> XCConfigurationList {
        
        let configurationList = XCConfigurationList(buildConfigurations: [ ])
        pbxproj.add(object: configurationList)

        let addSettings: (XCBuildConfiguration) throws -> Void = { configuration in
            let frameworkParentDirectory = try resourceLocator.projectDescription().parentDirectory
            configuration.buildSettings["FRAMEWORK_SEARCH_PATHS"] = frameworkParentDirectory.asString
            configuration.buildSettings["LIBRARY_SEARCH_PATHS"] = frameworkParentDirectory.asString
            configuration.buildSettings["SWIFT_FORCE_DYNAMIC_LINK_STDLIB"] = true
            configuration.buildSettings["SWIFT_FORCE_STATIC_LINK_STDLIB"] = false
            configuration.buildSettings["SWIFT_INCLUDE_PATHS"] = frameworkParentDirectory.asString
            configuration.buildSettings["SWIFT_VERSION"] = Constants.swiftVersion
            configuration.buildSettings["LD"] = "/usr/bin/true"
            configuration.buildSettings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "SWIFT_PACKAGE"
            configuration.buildSettings["OTHER_SWIFT_FLAGS"] = "-swift-version 4 -I \(frameworkParentDirectory.asString)"
        }
        
        for configuration in configurations {
            
            let variant: BuildSettingsProvider.Variant = (configuration.buildConfiguration == .debug) ? .debug : .release
            
            // Debug configuration
            let debugConfig = XCBuildConfiguration(name: configuration.name, baseConfiguration: nil, buildSettings: [:])
            pbxproj.add(object: debugConfig)
            
            debugConfig.buildSettings = BuildSettingsProvider.targetDefault(
                variant: variant,
                platform: .macOS,
                product: .framework,
                swift: true
            )
            
            configurationList.buildConfigurations.append(debugConfig)
            try addSettings(debugConfig)
            
        }

        return configurationList
    }

    // MARK: - Fileprivate

    fileprivate func generateProjectSettingsFor(
        buildConfiguration: BuildConfiguration,
        configuration: Configuration,
        project: Project,
        fileElements: ProjectFileElements,
        pbxproj: PBXProj,
        configurationList: XCConfigurationList,
        isRoot: Bool
    ) throws {
        
        let variant: BuildSettingsProvider.Variant = (buildConfiguration == .debug) ? .debug : .release
        let defaultConfigSettings = BuildSettingsProvider.projectDefault(variant: variant)
        let defaultSettingsAll = BuildSettingsProvider.projectDefault(variant: .all)
        let variantBuildConfiguration = XCBuildConfiguration(name: configuration.name, baseConfiguration: nil, buildSettings: [:])

        var settings: [String: Any] = [:]
        extend(buildSettings: &settings, with: defaultSettingsAll)
        extend(buildSettings: &settings, with: project.settings?.base ?? [:])
        extend(buildSettings: &settings, with: defaultConfigSettings)
        
        let projectBuildSettings: BuildSettings
        let xcconfig: AbsolutePath?
        
        if isRoot {
            projectBuildSettings = configuration.settings
            xcconfig = configuration.xcconfig
        } else {
            
            /// If any configurations in the project match the root project configuration name, then merge the settings
            /// else, If any build configuration types (debug, release) match then select the first one. This is because
            /// a dependency might only specify Debug and Release where the root project would specify Debug, UAT and Release.
            
            let projectConfigurations = project.settings?.configurations
            let projectConfiguration = projectConfigurations?.first(where: { $0.name == configuration.name }) ?? projectConfigurations?.first(where: { $0.buildConfiguration == buildConfiguration })
            
            projectBuildSettings = projectConfiguration?.settings ?? [:]
            xcconfig = projectConfiguration?.xcconfig
            
        }
        
        extend(buildSettings: &settings, with: projectBuildSettings)
        
        variantBuildConfiguration.baseConfiguration = xcconfig.flatMap(fileElements.file)
        variantBuildConfiguration.buildSettings = settings
        
        pbxproj.add(object: variantBuildConfiguration)
        configurationList.buildConfigurations.append(variantBuildConfiguration)
    }

    fileprivate func generateTargetSettingsFor(
        target: Target,
        buildConfiguration: BuildConfiguration,
        configuration: Configuration,
        fileElements: ProjectFileElements,
        pbxproj: PBXProj,
        configurationList: XCConfigurationList,
        sourceRootPath: AbsolutePath
    ) throws {
        
        let product = settingsProviderProduct(target)
        let platform = settingsProviderPlatform(target)

        let defaultConfigSettings = BuildSettingsProvider.targetDefault(platform: platform, product: product)

        var settings: [String: Any] = [:]
        
        extend(buildSettings: &settings, with: defaultConfigSettings)

        /// If any configurations in the project match the root project configuration name, then merge the settings
        /// else, If any of the default build configuration types (Debug, Release) match then assign using that.
        
        let targetSettings = target.settings?.buildSettings
        extend(buildSettings: &settings, with: targetSettings?[configuration.name] ?? targetSettings?[buildConfiguration.xcodeValue] ?? [:])
        
        let variantBuildConfiguration = XCBuildConfiguration(name: configuration.name, baseConfiguration: nil, buildSettings: [:])

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
        
        if target.product == .staticFramework {
            settings["MACH_O_TYPE"] = "staticlib"
        }

        variantBuildConfiguration.buildSettings = settings
        pbxproj.add(object: variantBuildConfiguration)
        configurationList.buildConfigurations.append(variantBuildConfiguration)
    }

    fileprivate func settingsProviderPlatform(_ target: Target) -> BuildSettingsProvider.Platform? {
        var platform: BuildSettingsProvider.Platform?
        switch target.platform {
        case .iOS: platform = .iOS
        case .macOS: platform = .macOS
        case .tvOS: platform = .tvOS
//        case .watchOS: platform = .watchOS
        }
        return platform
    }

    fileprivate func settingsProviderProduct(_ target: Target) -> BuildSettingsProvider.Product? {
        switch target.product {
        case .app:
            return .application
        case .dynamicLibrary:
            return .dynamicLibrary
        case .staticLibrary:
            return .staticLibrary
        case .framework, .staticFramework:
            return .framework
        default:
            return nil
        }
    }

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
