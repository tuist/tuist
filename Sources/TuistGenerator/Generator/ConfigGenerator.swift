import Basic
import Foundation
import TuistCore
import TuistSupport
import XcodeProj

protocol ConfigGenerating: AnyObject {
    func generateProjectConfig(project: Project,
                               pbxproj: PBXProj,
                               fileElements: ProjectFileElements) throws -> XCConfigurationList

    func generateTargetConfig(_ target: Target,
                              pbxTarget: PBXTarget,
                              pbxproj: PBXProj,
                              projectSettings: Settings,
                              fileElements: ProjectFileElements,
                              graph: Graphing,
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
                               fileElements: ProjectFileElements) throws -> XCConfigurationList {
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
        var settings = try defaultSettingsProvider.projectSettings(project: project,
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
        variantBuildConfiguration.buildSettings = settings.toAny()
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
        var settings = try defaultSettingsProvider.targetSettings(target: target,
                                                                  buildConfiguration: buildConfiguration)
        updateTargetDerived(buildSettings: &settings,
                            target: target,
                            graph: graph,
                            sourceRootPath: sourceRootPath)

        settingsHelper.extend(buildSettings: &settings, with: target.settings?.base ?? [:])
        settingsHelper.extend(buildSettings: &settings, with: configuration?.settings ?? [:])

        let variantBuildConfiguration = XCBuildConfiguration(name: buildConfiguration.xcodeValue,
                                                             baseConfiguration: nil,
                                                             buildSettings: [:])
        if let variantConfig = configuration, let xcconfig = variantConfig.xcconfig {
            let fileReference = fileElements.file(path: xcconfig)
            variantBuildConfiguration.baseConfiguration = fileReference
        }

        variantBuildConfiguration.buildSettings = settings.toAny()
        pbxproj.add(object: variantBuildConfiguration)
        configurationList.buildConfigurations.append(variantBuildConfiguration)
    }

    private func updateTargetDerived(buildSettings settings: inout [String: SettingValue],
                                     target: Target,
                                     graph: Graphing,
                                     sourceRootPath: AbsolutePath) {
        settings.merge(generalTargetDerivedSettings(target: target, sourceRootPath: sourceRootPath)) { $1 }
        settings.merge(testBundleTargetDerivedSettings(target: target, graph: graph, sourceRootPath: sourceRootPath)) { $1 }
        settings.merge(deploymentTargetDerivedSettings(target: target)) { $1 }
        settings.merge(watchTargetDerivedSettings(target: target, graph: graph, sourceRootPath: sourceRootPath)) { $1 }
    }

    private func generalTargetDerivedSettings(target: Target,
                                              sourceRootPath: AbsolutePath) -> [String: SettingValue] {
        var settings: [String: SettingValue] = [:]
        settings["PRODUCT_BUNDLE_IDENTIFIER"] = .string(target.bundleId)

        // Info.plist
        if let infoPlist = target.infoPlist, let path = infoPlist.path {
            let relativePath = path.relative(to: sourceRootPath).pathString
            settings["INFOPLIST_FILE"] = .string("\(relativePath)")
        }

        if let entitlements = target.entitlements {
            settings["CODE_SIGN_ENTITLEMENTS"] = .string("$(SRCROOT)/\(entitlements.relative(to: sourceRootPath).pathString)")
        }
        settings["SDKROOT"] = .string(target.platform.xcodeSdkRoot)
        settings["SUPPORTED_PLATFORMS"] = .string(target.platform.xcodeSupportedPlatforms)
        // TODO: We should show a warning here
        if settings["SWIFT_VERSION"] == nil {
            settings["SWIFT_VERSION"] = .string(Constants.swiftVersion)
        }

        if target.product == .staticFramework {
            settings["MACH_O_TYPE"] = "staticlib"
        }

        settings["PRODUCT_NAME"] = .string(target.productName)

        return settings
    }

    private func testBundleTargetDerivedSettings(target: Target,
                                                 graph: Graphing,
                                                 sourceRootPath: AbsolutePath) -> [String: SettingValue] {
        guard target.product.testsBundle else {
            return [:]
        }

        let targetDependencies = graph.targetDependencies(path: sourceRootPath, name: target.name)
        let appDependency = targetDependencies.first { targetNode in
            targetNode.target.product == .app
        }

        guard let app = appDependency else {
            return [:]
        }

        var settings: [String: SettingValue] = [:]
        settings["TEST_TARGET_NAME"] = .string("\(app.target.productName)")
        if target.product == .unitTests {
            settings["TEST_HOST"] = .string("$(BUILT_PRODUCTS_DIR)/\(app.target.productNameWithExtension)/\(app.target.productName)")
            settings["BUNDLE_LOADER"] = "$(TEST_HOST)"
        }

        return settings
    }

    private func deploymentTargetDerivedSettings(target: Target) -> [String: SettingValue] {
        guard let deploymentTarget = target.deploymentTarget else {
            return [:]
        }

        var settings: [String: SettingValue] = [:]

        switch deploymentTarget {
        case let .iOS(version, devices):
            var deviceFamilyValues: [Int] = []
            if devices.contains(.iphone) { deviceFamilyValues.append(1) }
            if devices.contains(.ipad) { deviceFamilyValues.append(2) }

            settings["TARGETED_DEVICE_FAMILY"] = .string(deviceFamilyValues.map { "\($0)" }.joined(separator: ","))
            settings["IPHONEOS_DEPLOYMENT_TARGET"] = .string(version)

            if devices.contains(.ipad), devices.contains(.mac) {
                settings["SUPPORTS_MACCATALYST"] = "YES"
                settings["DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER"] = "YES"
            }
        case let .macOS(version):
            settings["MACOSX_DEPLOYMENT_TARGET"] = .string(version)
        }

        return settings
    }

    private func watchTargetDerivedSettings(target: Target,
                                            graph: Graphing,
                                            sourceRootPath: AbsolutePath) -> [String: SettingValue] {
        guard target.product == .watch2App else {
            return [:]
        }

        let targetDependencies = graph.targetDependencies(path: sourceRootPath, name: target.name)
        guard let watchExtension = targetDependencies.first(where: { $0.target.product == .watch2Extension }) else {
            return [:]
        }

        return [
            "IBSC_MODULE": .string(watchExtension.target.productName),
        ]
    }
}
