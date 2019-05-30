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

    private let fileGenerator: FileGenerating
    private let defaultSettingsProvider: DefaultSettingsProviding

    // MARK: - Init

    init(fileGenerator: FileGenerating = FileGenerator(),
         defaultSettingsProvider: DefaultSettingsProviding = DefaultSettingsProvider()) {
        self.fileGenerator = fileGenerator
        self.defaultSettingsProvider = defaultSettingsProvider
    }

    // MARK: - ConfigGenerating

    func generateProjectConfig(project: Project,
                               pbxproj: PBXProj,
                               fileElements: ProjectFileElements,
                               options _: GenerationOptions) throws -> XCConfigurationList {
        /// Configuration list
        let configurationList = XCConfigurationList(buildConfigurations: [])
        pbxproj.add(object: configurationList)

        try project.settings.configurations.sortedByBuildConfigurationName().forEach {
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
        let configurationsTuples: [(BuildConfiguration, Configuration?)] = buildConfigurations
            .map { buildConfiguration in
                if let configuration = target.settings?.configurations[buildConfiguration] {
                    return (buildConfiguration, configuration)
                }
                return (buildConfiguration, nil)
            }
        let configurations = Dictionary(uniqueKeysWithValues: configurationsTuples)
        let nonEmptyConfigurations = !configurations.isEmpty ? configurations : Settings.default.configurations
        let orderedConfigurations = nonEmptyConfigurations.sortedByBuildConfigurationName()
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
        let settingsHelper = SettingsHelper()
        var settings = defaultSettingsProvider.projectSettings(project: project,
                                                               buildConfiguration: buildConfiguration)
        settingsHelper.extend(buildSettings: &settings, with: project.settings.base)

        let variantBuildConfiguration = XCBuildConfiguration(name: buildConfiguration.xcodeValue,
                                                             baseConfiguration: nil,
                                                             buildSettings: [:])
        if let variantConfig = configuration {
            settingsHelper.extend(buildSettings: &settings, with: variantConfig.settings)
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
        let settingsHelper = SettingsHelper()
        var settings = defaultSettingsProvider.targetSettings(target: target,
                                                              buildConfiguration: buildConfiguration)
        settingsHelper.extend(buildSettings: &settings, with: target.settings?.base ?? [:])
        settingsHelper.extend(buildSettings: &settings, with: configuration?.settings ?? [:])

        let variantBuildConfiguration = XCBuildConfiguration(name: buildConfiguration.xcodeValue,
                                                             baseConfiguration: nil,
                                                             buildSettings: [:])
        if let variantConfig = configuration, let xcconfig = variantConfig.xcconfig {
            let fileReference = fileElements.file(path: xcconfig)
            variantBuildConfiguration.baseConfiguration = fileReference
        }

        updateTargetDerived(buildSettings: &settings,
                            target: target,
                            graph: graph,
                            sourceRootPath: sourceRootPath)

        variantBuildConfiguration.buildSettings = settings
        pbxproj.add(object: variantBuildConfiguration)
        configurationList.buildConfigurations.append(variantBuildConfiguration)
    }

    private func updateTargetDerived(buildSettings settings: inout [String: Any],
                                     target: Target,
                                     graph: Graphing,
                                     sourceRootPath: AbsolutePath) {
        settings["PRODUCT_BUNDLE_IDENTIFIER"] = target.bundleId
        if let infoPlist = target.infoPlist {
            settings["INFOPLIST_FILE"] = "$(SRCROOT)/\(infoPlist.path.relative(to: sourceRootPath).pathString)"
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
    }
}
