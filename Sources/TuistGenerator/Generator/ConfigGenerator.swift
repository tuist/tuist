import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import XcodeProj

protocol ConfigGenerating: AnyObject {
    func generateProjectConfig(project: Project,
                               pbxproj: PBXProj,
                               fileElements: ProjectFileElements) throws -> XCConfigurationList

    func generateTargetConfig(_ target: Target,
                              project: Project,
                              pbxTarget: PBXTarget,
                              pbxproj: PBXProj,
                              projectSettings: Settings,
                              fileElements: ProjectFileElements,
                              graphTraverser: ValueGraphTraverser,
                              sourceRootPath: AbsolutePath) throws
}

final class ConfigGenerator: ConfigGenerating {
    // MARK: - Attributes

    private let fileGenerator: FileGenerating
    private let defaultSettingsProvider: DefaultSettingsProviding

    // MARK: - Init

    init(fileGenerator: FileGenerating = FileGenerator(),
         defaultSettingsProvider: DefaultSettingsProviding = DefaultSettingsProvider())
    {
        self.fileGenerator = fileGenerator
        self.defaultSettingsProvider = defaultSettingsProvider
    }

    // MARK: - ConfigGenerating

    func generateProjectConfig(project: Project,
                               pbxproj: PBXProj,
                               fileElements: ProjectFileElements) throws -> XCConfigurationList
    {
        /// Configuration list
        let defaultConfiguration = project.settings.defaultReleaseBuildConfiguration()
            ?? project.settings.defaultDebugBuildConfiguration()
        let configurationList = XCConfigurationList(buildConfigurations: [],
                                                    defaultConfigurationName: defaultConfiguration?.name)
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
                              project: Project,
                              pbxTarget: PBXTarget,
                              pbxproj: PBXProj,
                              projectSettings: Settings,
                              fileElements: ProjectFileElements,
                              graphTraverser: ValueGraphTraverser,
                              sourceRootPath: AbsolutePath) throws
    {
        let defaultConfiguration = projectSettings.defaultReleaseBuildConfiguration()
            ?? projectSettings.defaultDebugBuildConfiguration()
        let configurationList = XCConfigurationList(buildConfigurations: [],
                                                    defaultConfigurationName: defaultConfiguration?.name)
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
        let swiftVersion = try System.shared.swiftVersion()
        try orderedConfigurations.forEach {
            try generateTargetSettingsFor(target: target,
                                          project: project,
                                          buildConfiguration: $0.key,
                                          configuration: $0.value,
                                          fileElements: fileElements,
                                          graphTraverser: graphTraverser,
                                          pbxproj: pbxproj,
                                          configurationList: configurationList,
                                          swiftVersion: swiftVersion,
                                          sourceRootPath: sourceRootPath)
        }
    }

    // MARK: - Fileprivate

    private func generateProjectSettingsFor(buildConfiguration: BuildConfiguration,
                                            configuration: Configuration?,
                                            project: Project,
                                            fileElements: ProjectFileElements,
                                            pbxproj: PBXProj,
                                            configurationList: XCConfigurationList) throws
    {
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
                                           project: Project,
                                           buildConfiguration: BuildConfiguration,
                                           configuration: Configuration?,
                                           fileElements: ProjectFileElements,
                                           graphTraverser: ValueGraphTraverser,
                                           pbxproj: PBXProj,
                                           configurationList: XCConfigurationList,
                                           swiftVersion: String,
                                           sourceRootPath: AbsolutePath) throws
    {
        let settingsHelper = SettingsHelper()
        var settings = try defaultSettingsProvider.targetSettings(target: target,
                                                                  project: project,
                                                                  buildConfiguration: buildConfiguration)
        updateTargetDerived(buildSettings: &settings,
                            target: target,
                            graphTraverser: graphTraverser,
                            swiftVersion: swiftVersion,
                            projectPath: project.path,
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

    private func updateTargetDerived(buildSettings settings: inout SettingsDictionary,
                                     target: Target,
                                     graphTraverser: ValueGraphTraverser,
                                     swiftVersion: String,
                                     projectPath: AbsolutePath,
                                     sourceRootPath: AbsolutePath)
    {
        settings.merge(generalTargetDerivedSettings(target: target, swiftVersion: swiftVersion, sourceRootPath: sourceRootPath)) { $1 }
        settings.merge(testBundleTargetDerivedSettings(target: target, graphTraverser: graphTraverser, projectPath: projectPath)) { $1 }
        settings.merge(deploymentTargetDerivedSettings(target: target)) { $1 }
        settings.merge(watchTargetDerivedSettings(target: target, graphTraverser: graphTraverser, projectPath: projectPath)) { $1 }
    }

    private func generalTargetDerivedSettings(target: Target,
                                              swiftVersion: String,
                                              sourceRootPath: AbsolutePath) -> SettingsDictionary
    {
        var settings: SettingsDictionary = [:]
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

        if settings["SWIFT_VERSION"] == nil {
            settings["SWIFT_VERSION"] = .string(swiftVersion)
        }

        if target.product == .staticFramework {
            settings["MACH_O_TYPE"] = "staticlib"
        }

        settings["PRODUCT_NAME"] = .string(target.productName)

        return settings
    }

    private func testBundleTargetDerivedSettings(target: Target,
                                                 graphTraverser: ValueGraphTraverser,
                                                 projectPath: AbsolutePath) -> SettingsDictionary
    {
        guard target.product.testsBundle else {
            return [:]
        }

        let targetDependencies = graphTraverser.directTargetDependencies(path: projectPath, name: target.name)
        let appDependency = targetDependencies.first { $0.product == .app }

        guard let app = appDependency else {
            return [:]
        }

        var settings: SettingsDictionary = [:]
        settings["TEST_TARGET_NAME"] = .string("\(app.productName)")
        if target.product == .unitTests {
            settings["TEST_HOST"] = .string("$(BUILT_PRODUCTS_DIR)/\(app.productNameWithExtension)/\(app.productName)")
            settings["BUNDLE_LOADER"] = "$(TEST_HOST)"
        }

        return settings
    }

    private func deploymentTargetDerivedSettings(target: Target) -> SettingsDictionary {
        guard let deploymentTarget = target.deploymentTarget else {
            return [:]
        }

        var settings: SettingsDictionary = [:]

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
                                            graphTraverser: ValueGraphTraverser,
                                            projectPath: AbsolutePath) -> SettingsDictionary
    {
        guard target.product == .watch2App else {
            return [:]
        }

        let targetDependencies = graphTraverser.directTargetDependencies(path: projectPath, name: target.name)
        guard let watchExtension = targetDependencies.first(where: { $0.product == .watch2Extension }) else {
            return [:]
        }

        return [
            "IBSC_MODULE": .string(watchExtension.productName),
        ]
    }
}
