import Basic
import Foundation
import TuistCore
import xcodeproj

protocol ConfigGenerating: AnyObject {
    func generateProjectConfig(project: Project,
                               pbxproj: PBXProj,
                               fileElements: ProjectFileElements,
                               options: GenerationOptions) throws -> XCConfigurationList

    func generateManifestsConfig(pbxproj: PBXProj,
                                 options: GenerationOptions,
                                 resourceLocator: ResourceLocating) throws -> XCConfigurationList

    func generateTargetConfig(_ target: Target,
                              pbxTarget: PBXTarget,
                              pbxproj: PBXProj,
                              fileElements: ProjectFileElements,
                              options: GenerationOptions,
                              sourceRootPath: AbsolutePath) throws
}

final class ConfigGenerator: ConfigGenerating {
    // MARK: - Attributes

    let fileGenerator: FileGenerating

    // MARK: - Init

    init(fileGenerator: FileGenerating = FileGenerator()) {
        self.fileGenerator = fileGenerator
    }

    // MARK: - ConfigGenerating

    func generateProjectConfig(project: Project,
                               pbxproj: PBXProj,
                               fileElements: ProjectFileElements,
                               options: GenerationOptions) throws -> XCConfigurationList {
        /// Configuration list
        let configurationList = XCConfigurationList(buildConfigurations: [])
        pbxproj.add(object: configurationList)

        if options.buildConfiguration == .debug {
            try generateProjectSettingsFor(buildConfiguration: .debug,
                                           configuration: project.settings?.debug,
                                           project: project,
                                           fileElements: fileElements,
                                           pbxproj: pbxproj,
                                           configurationList: configurationList)
        }

        if options.buildConfiguration == .release {
            try generateProjectSettingsFor(buildConfiguration: .release,
                                           configuration: project.settings?.release,
                                           project: project,
                                           fileElements: fileElements,
                                           pbxproj: pbxproj,
                                           configurationList: configurationList)
        }
        return configurationList
    }

    func generateTargetConfig(_ target: Target,
                              pbxTarget: PBXTarget,
                              pbxproj: PBXProj,
                              fileElements: ProjectFileElements,
                              options: GenerationOptions,
                              sourceRootPath: AbsolutePath) throws {
        let configurationList = XCConfigurationList(buildConfigurations: [])
        pbxproj.add(object: configurationList)
        pbxTarget.buildConfigurationList = configurationList

        if options.buildConfiguration == .debug {
            try generateTargetSettingsFor(target: target,
                                          buildConfiguration: .debug,
                                          configuration: target.settings?.debug,
                                          fileElements: fileElements,
                                          pbxproj: pbxproj,
                                          configurationList: configurationList,
                                          sourceRootPath: sourceRootPath)
        }

        if options.buildConfiguration == .release {
            try generateTargetSettingsFor(target: target,
                                          buildConfiguration: .release,
                                          configuration: target.settings?.release,
                                          fileElements: fileElements,
                                          pbxproj: pbxproj,
                                          configurationList: configurationList,
                                          sourceRootPath: sourceRootPath)
        }
    }

    func generateManifestsConfig(pbxproj: PBXProj,
                                 options: GenerationOptions,
                                 resourceLocator: ResourceLocating = ResourceLocator()) throws -> XCConfigurationList {
        let configurationList = XCConfigurationList(buildConfigurations: [])
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
        if options.buildConfiguration == .debug {
            let debugConfig = XCBuildConfiguration(name: "Debug", baseConfiguration: nil, buildSettings: [:])
            pbxproj.add(object: debugConfig)
            debugConfig.buildSettings = BuildSettingsProvider.targetDefault(variant: .debug, platform: .macOS, product: .framework, swift: true)
            configurationList.buildConfigurations.append(debugConfig)
            try addSettings(debugConfig)
        }
        if options.buildConfiguration == .release {
            let releaseConfig = XCBuildConfiguration(name: "Release", baseConfiguration: nil, buildSettings: [:])
            pbxproj.add(object: releaseConfig)
            releaseConfig.buildSettings = BuildSettingsProvider.targetDefault(variant: .release, platform: .macOS, product: .framework, swift: true)
            configurationList.buildConfigurations.append(releaseConfig)
            try addSettings(releaseConfig)
        }
        return configurationList
    }

    // MARK: - Fileprivate

    fileprivate func generateProjectSettingsFor(buildConfiguration: BuildConfiguration,
                                                configuration: Configuration?,
                                                project: Project,
                                                fileElements: ProjectFileElements,
                                                pbxproj: PBXProj,
                                                configurationList: XCConfigurationList) throws {
        let variant: BuildSettingsProvider.Variant = (buildConfiguration == .debug) ? .debug : .release
        let defaultConfigSettings = BuildSettingsProvider.projectDefault(variant: variant)
        let defaultSettingsAll = BuildSettingsProvider.projectDefault(variant: .all)

        var settings: [String: Any] = [:]
        extend(buildSettings: &settings, with: defaultSettingsAll)
        extend(buildSettings: &settings, with: project.settings?.base ?? [:])
        extend(buildSettings: &settings, with: defaultConfigSettings)

        let variantBuildConfiguration = XCBuildConfiguration(name: buildConfiguration.rawValue.capitalized, baseConfiguration: nil, buildSettings: [:])
        if let variantConfig = configuration {
            extend(buildSettings: &settings, with: variantConfig.settings)
            if let xcconfig = variantConfig.xcconfig {
                let fileReference = fileElements.file(path: xcconfig)
                variantBuildConfiguration.baseConfiguration = fileReference
            }
        }
        variantBuildConfiguration.buildSettings = settings
        pbxproj.add(object: variantBuildConfiguration)
        configurationList.buildConfigurations.append(variantBuildConfiguration)
    }

    fileprivate func generateTargetSettingsFor(target: Target,
                                               buildConfiguration: BuildConfiguration,
                                               configuration: Configuration?,
                                               fileElements: ProjectFileElements,
                                               pbxproj: PBXProj,
                                               configurationList: XCConfigurationList,
                                               sourceRootPath: AbsolutePath) throws {
        let product = settingsProviderProduct(target)
        let platform = settingsProviderPlatform(target)

        let defaultConfigSettings = BuildSettingsProvider.targetDefault(platform: platform, product: product)

        var settings: [String: Any] = [:]
        extend(buildSettings: &settings, with: defaultConfigSettings)
        extend(buildSettings: &settings, with: target.settings?.base ?? [:])
        extend(buildSettings: &settings, with: configuration?.settings ?? [:])

        let variantBuildConfiguration = XCBuildConfiguration(name: buildConfiguration.rawValue.capitalized, baseConfiguration: nil, buildSettings: [:])
        if let variantConfig = configuration {
            if let xcconfig = variantConfig.xcconfig {
                let fileReference = fileElements.file(path: xcconfig)
                variantBuildConfiguration.baseConfiguration = fileReference
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
        case .framework:
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
