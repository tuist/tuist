import Basic
import Foundation
import TuistCore
import XcodeProj

protocol ConfigGenerating: AnyObject {
    func generateProjectConfig(project: Project,
                               pbxproj: PBXProj,
                               fileElements: ProjectFileElements,
                               options: GenerationOptions) throws -> XCConfigurationList

    func generateTargetConfig(_ target: Target,
                              pbxTarget: PBXTarget,
                              pbxproj: PBXProj,
                              projectSettings: Settings,
                              fileElements: ProjectFileElements,
                              graph: Graphing,
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
                               options _: GenerationOptions) throws -> XCConfigurationList {
        /// Configuration list
        let configurationList = XCConfigurationList(buildConfigurations: [])
        pbxproj.add(object: configurationList)

        try project.settings.orderedConfigurations().forEach {
            try generateProjectSettingsFor(buildConfiguration: $0.key,
                                           configuration: $0.value,
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
                              projectSettings: Settings,
                              fileElements: ProjectFileElements,
                              graph: Graphing,
                              options _: GenerationOptions,
                              sourceRootPath: AbsolutePath) throws {
        let configurationList = XCConfigurationList(buildConfigurations: [])
        pbxproj.add(object: configurationList)
        pbxTarget.buildConfigurationList = configurationList

        let projectBuildConfigurations = projectSettings.configurations.keys
        let targetConfigurations = target.settings?.configurations ?? [:]
        let targetBuildConfigurations = targetConfigurations.keys
        let buildConfigurations = Set(projectBuildConfigurations).union(targetBuildConfigurations)
        let configurationsTuples: [(BuildConfiguration, Configuration?)] = buildConfigurations.map {
            if let configuration = target.settings?.configurations[$0] {
                return ($0, configuration)
            }
            return ($0, nil)
        }
        let configurations = Dictionary(uniqueKeysWithValues: configurationsTuples)
        let nonEmptyConfigurations = !configurations.isEmpty ? configurations : Settings.default.configurations
        let orderedConfigurations = Settings.ordered(configurations: nonEmptyConfigurations)
        try orderedConfigurations.forEach {
            try generateTargetSettingsFor(target: target,
                                          buildConfiguration: $0.key,
                                          configuration: $0.value,
                                          fileElements: fileElements,
                                          graph: graph,
                                          pbxproj: pbxproj,
                                          configurationList: configurationList,
                                          sourceRootPath: sourceRootPath)
        }
    }

    // MARK: - Fileprivate

    private func generateProjectSettingsFor(buildConfiguration: BuildConfiguration,
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
        extend(buildSettings: &settings, with: project.settings.base)
        extend(buildSettings: &settings, with: defaultConfigSettings)

        let variantBuildConfiguration = XCBuildConfiguration(name: buildConfiguration.xcodeValue,
                                                             baseConfiguration: nil,
                                                             buildSettings: [:])
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

    private func generateTargetSettingsFor(target: Target,
                                           buildConfiguration: BuildConfiguration,
                                           configuration: Configuration?,
                                           fileElements: ProjectFileElements,
                                           graph: Graphing,
                                           pbxproj: PBXProj,
                                           configurationList: XCConfigurationList,
                                           sourceRootPath: AbsolutePath) throws {
        let product = settingsProviderProduct(target)
        let platform = settingsProviderPlatform(target)
        let variant: BuildSettingsProvider.Variant = (buildConfiguration == .debug) ? .debug : .release

        var settings: [String: Any] = [:]
        extend(buildSettings: &settings, with: BuildSettingsProvider.targetDefault(variant: .all,
                                                                                   platform: platform,
                                                                                   product: product,
                                                                                   swift: true))
        extend(buildSettings: &settings, with: BuildSettingsProvider.targetDefault(variant: variant,
                                                                                   platform: platform,
                                                                                   product: product,
                                                                                   swift: true))
        extend(buildSettings: &settings, with: target.settings?.base ?? [:])
        extend(buildSettings: &settings, with: configuration?.settings ?? [:])

        let variantBuildConfiguration = XCBuildConfiguration(name: buildConfiguration.xcodeValue,
                                                             baseConfiguration: nil,
                                                             buildSettings: [:])
        if let variantConfig = configuration {
            if let xcconfig = variantConfig.xcconfig {
                let fileReference = fileElements.file(path: xcconfig)
                variantBuildConfiguration.baseConfiguration = fileReference
            }
        }

        /// Target attributes
        settings["PRODUCT_BUNDLE_IDENTIFIER"] = target.bundleId
        if let infoPlist = target.infoPlist {
            settings["INFOPLIST_FILE"] = "$(SRCROOT)/\(infoPlist.relative(to: sourceRootPath).pathString)"
        }
        if let entitlements = target.entitlements {
            settings["CODE_SIGN_ENTITLEMENTS"] = "$(SRCROOT)/\(entitlements.relative(to: sourceRootPath).pathString)"
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

        if target.product.testsBundle {
            let appDependency = graph.targetDependencies(path: sourceRootPath, name: target.name).first { targetNode in
                targetNode.target.product == .app
            }

            if let app = appDependency {
                settings["TEST_TARGET_NAME"] = "\(app.target.name)"

                if target.product == .unitTests {
                    settings["TEST_HOST"] = "$(BUILT_PRODUCTS_DIR)/\(app.target.productNameWithExtension)/\(app.target.name)"
                    settings["BUNDLE_LOADER"] = "$(TEST_HOST)"
                }
            }
        }

        variantBuildConfiguration.buildSettings = settings
        pbxproj.add(object: variantBuildConfiguration)
        configurationList.buildConfigurations.append(variantBuildConfiguration)
    }

    private func settingsProviderPlatform(_ target: Target) -> BuildSettingsProvider.Platform? {
        var platform: BuildSettingsProvider.Platform?
        switch target.platform {
        case .iOS: platform = .iOS
        case .macOS: platform = .macOS
        case .tvOS: platform = .tvOS
//        case .watchOS: platform = .watchOS
        }
        return platform
    }

    private func settingsProviderProduct(_ target: Target) -> BuildSettingsProvider.Product? {
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

    private func extend(buildSettings: inout [String: Any], with other: [String: Any]) {
        other.forEach { key, value in
            if buildSettings[key] == nil || (value as? String)?.contains("$(inherited)") == false {
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
