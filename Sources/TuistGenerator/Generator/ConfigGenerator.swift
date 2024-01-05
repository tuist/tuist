import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XcodeProj

protocol ConfigGenerating: AnyObject {
    func generateProjectConfig(
        project: Project,
        pbxproj: PBXProj,
        fileElements: ProjectFileElements
    ) throws -> XCConfigurationList

    func generateTargetConfig(
        _ target: Target,
        project: Project,
        pbxTarget: PBXTarget,
        pbxproj: PBXProj,
        projectSettings: Settings,
        fileElements: ProjectFileElements,
        graphTraverser: GraphTraversing,
        sourceRootPath: AbsolutePath
    ) throws
}

// swiftlint:disable:next type_body_length
final class ConfigGenerator: ConfigGenerating {
    // MARK: - Attributes

    private let fileGenerator: FileGenerating
    private let defaultSettingsProvider: DefaultSettingsProviding

    // MARK: - Init

    init(
        fileGenerator: FileGenerating = FileGenerator(),
        defaultSettingsProvider: DefaultSettingsProviding = DefaultSettingsProvider()
    ) {
        self.fileGenerator = fileGenerator
        self.defaultSettingsProvider = defaultSettingsProvider
    }

    // MARK: - ConfigGenerating

    func generateProjectConfig(
        project: Project,
        pbxproj: PBXProj,
        fileElements: ProjectFileElements
    ) throws -> XCConfigurationList {
        /// Configuration list
        let defaultConfiguration = project.settings.defaultReleaseBuildConfiguration()
            ?? project.settings.defaultDebugBuildConfiguration()
        let configurationList = XCConfigurationList(
            buildConfigurations: [],
            defaultConfigurationName: defaultConfiguration?.name
        )
        pbxproj.add(object: configurationList)

        try project.settings.configurations.sortedByBuildConfigurationName().forEach {
            try generateProjectSettingsFor(
                buildConfiguration: $0.key,
                configuration: $0.value,
                project: project,
                fileElements: fileElements,
                pbxproj: pbxproj,
                configurationList: configurationList
            )
        }

        return configurationList
    }

    func generateTargetConfig(
        _ target: Target,
        project: Project,
        pbxTarget: PBXTarget,
        pbxproj: PBXProj,
        projectSettings: Settings,
        fileElements: ProjectFileElements,
        graphTraverser: GraphTraversing,
        sourceRootPath: AbsolutePath
    ) throws {
        let defaultConfiguration = projectSettings.defaultReleaseBuildConfiguration()
            ?? projectSettings.defaultDebugBuildConfiguration()
        let configurationList = XCConfigurationList(
            buildConfigurations: [],
            defaultConfigurationName: defaultConfiguration?.name
        )
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
            try generateTargetSettingsFor(
                target: target,
                project: project,
                buildConfiguration: $0.key,
                configuration: $0.value,
                fileElements: fileElements,
                graphTraverser: graphTraverser,
                pbxproj: pbxproj,
                configurationList: configurationList,
                sourceRootPath: sourceRootPath
            )
        }
    }

    // MARK: - Fileprivate

    private func generateProjectSettingsFor(
        buildConfiguration: BuildConfiguration,
        configuration: Configuration?,
        project: Project,
        fileElements: ProjectFileElements,
        pbxproj: PBXProj,
        configurationList: XCConfigurationList
    ) throws {
        let settingsHelper = SettingsHelper()
        var settings = try defaultSettingsProvider.projectSettings(
            project: project,
            buildConfiguration: buildConfiguration
        )
        settingsHelper.extend(buildSettings: &settings, with: project.settings.base)

        let variantBuildConfiguration = XCBuildConfiguration(
            name: buildConfiguration.xcodeValue,
            baseConfiguration: nil,
            buildSettings: [:]
        )
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

    private func generateTargetSettingsFor(
        target: Target,
        project: Project,
        buildConfiguration: BuildConfiguration,
        configuration: Configuration?,
        fileElements: ProjectFileElements,
        graphTraverser: GraphTraversing,
        pbxproj: PBXProj,
        configurationList: XCConfigurationList,
        sourceRootPath: AbsolutePath
    ) throws {
        let settingsHelper = SettingsHelper()

        var settings: SettingsDictionary = try defaultSettingsProvider.targetSettings(
            target: target,
            project: project,
            buildConfiguration: buildConfiguration
        )

        updateTargetDerived(
            buildSettings: &settings,
            target: target,
            graphTraverser: graphTraverser,
            project: project,
            sourceRootPath: sourceRootPath
        )

        settingsHelper.extend(buildSettings: &settings, with: target.settings?.base ?? [:])
        settingsHelper.extend(buildSettings: &settings, with: configuration?.settings ?? [:])

        let variantBuildConfiguration = XCBuildConfiguration(
            name: buildConfiguration.xcodeValue,
            baseConfiguration: nil,
            buildSettings: [:]
        )
        if let variantConfig = configuration, let xcconfig = variantConfig.xcconfig {
            let fileReference = fileElements.file(path: xcconfig)
            variantBuildConfiguration.baseConfiguration = fileReference
        }

        variantBuildConfiguration.buildSettings = settings.toAny()
        pbxproj.add(object: variantBuildConfiguration)
        configurationList.buildConfigurations.append(variantBuildConfiguration)
    }

    private func updateTargetDerived(
        buildSettings settings: inout SettingsDictionary,
        target: Target,
        graphTraverser: GraphTraversing,
        project: Project,
        sourceRootPath: AbsolutePath
    ) {
        settings.merge(
            generalTargetDerivedSettings(
                target: target,
                sourceRootPath: sourceRootPath,
                project: project
            )
        ) { $1 }
        settings
            .merge(testBundleTargetDerivedSettings(target: target, graphTraverser: graphTraverser, projectPath: project.path)) {
                $1
            }
        settings.merge(destinationsDerivedSettings(target: target)) { $1 }
        settings.merge(deploymentTargetDerivedSettings(target: target)) { $1 }
        settings
            .merge(watchTargetDerivedSettings(target: target, graphTraverser: graphTraverser, projectPath: project.path)) { $1 }
        settings
            .merge(swiftMacrosDerivedSettings(target: target, graphTraverser: graphTraverser, projectPath: project.path)) {
                $1
            }
    }

    private func generalTargetDerivedSettings(
        target: Target,
        sourceRootPath: AbsolutePath,
        project: Project
    ) -> SettingsDictionary {
        var settings: SettingsDictionary = [:]
        settings["PRODUCT_BUNDLE_IDENTIFIER"] = .string(target.bundleId)

        // Info.plist
        if let infoPlist = target.infoPlist, let path = infoPlist.path {
            let relativePath = path.relative(to: sourceRootPath).pathString
            if project.xcodeProjPath.parentDirectory == sourceRootPath {
                settings["INFOPLIST_FILE"] = .string(relativePath)
            } else {
                settings["INFOPLIST_FILE"] = .string("$(SRCROOT)/\(relativePath)")
            }
        }

        // Entitlements
        if let entitlements = target.entitlements, let path = entitlements.path {
            let relativePath = path.relative(to: sourceRootPath).pathString
            if project.xcodeProjPath.parentDirectory == sourceRootPath {
                settings["CODE_SIGN_ENTITLEMENTS"] = .string(relativePath)
            } else {
                settings["CODE_SIGN_ENTITLEMENTS"] = .string("$(SRCROOT)/\(relativePath)")
            }
        }

        if target.supportedPlatforms.count == 1, let platform = target.supportedPlatforms.first {
            settings["SDKROOT"] = .string(platform.xcodeSdkRoot)
        } else {
            settings["SDKROOT"] = "auto"
        }

        if target.supportedPlatforms.count > 1 {
            let simulatorSDKs = target.supportedPlatforms.compactMap(\.xcodeSimulatorSDK)
            let platformSDKs = target.supportedPlatforms.map(\.xcodeDeviceSDK)
            settings["SUPPORTED_PLATFORMS"] = .string(
                [simulatorSDKs, platformSDKs].flatMap { $0 }.sorted()
                    .joined(separator: " ")
            )
        }

        if target.product == .staticFramework {
            settings["MACH_O_TYPE"] = "staticlib"
        }

        settings["PRODUCT_NAME"] = .string(target.productName)

        return settings
    }

    private func testBundleTargetDerivedSettings(
        target: Target,
        graphTraverser: GraphTraversing,
        projectPath: AbsolutePath
    ) -> SettingsDictionary {
        guard target.product.testsBundle else {
            return [:]
        }

        let targetDependencies = graphTraverser.directLocalTargetDependencies(path: projectPath, name: target.name).sorted()
        let appDependency = targetDependencies.first { $0.target.product.canHostTests() }

        guard let app = appDependency else {
            return [:]
        }

        var settings: SettingsDictionary = [:]
        settings["TEST_TARGET_NAME"] = .string("\(app.target.name)")
        if target.product == .unitTests {
            settings["TEST_HOST"] =
                .string(
                    "$(BUILT_PRODUCTS_DIR)/\(app.target.productNameWithExtension)/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/\(app.target.productName)"
                )
            settings["BUNDLE_LOADER"] = "$(TEST_HOST)"
        }

        return settings
    }

    private func swiftMacrosDerivedSettings(
        target: Target,
        graphTraverser: GraphTraversing,
        projectPath: AbsolutePath
    ) -> SettingsDictionary {
        let targets = graphTraverser.allSwiftMacroFrameworkTargets(path: projectPath, name: target.name)
        if targets.isEmpty { return [:] }
        var settings: SettingsDictionary = [:]
        settings["OTHER_SWIFT_FLAGS"] = .array(targets.flatMap { target in
            let macroExecutables = graphTraverser.directSwiftMacroExecutables(path: target.path, name: target.target.name)
            return macroExecutables.flatMap { macroExecutable in
                switch macroExecutable {
                case let .product(_, productName, _):
                    return [
                        "-load-plugin-executable",
                        "$BUILT_PRODUCTS_DIR/\(target.target.productNameWithExtension)/Macros/\(productName)#\(productName)",
                    ]
                default:
                    return []
                }
            }
        })
        return settings
    }

    private func destinationsDerivedSettings(target: Target) -> SettingsDictionary {
        var settings: SettingsDictionary = [:]

        var deviceFamilyValues: [Int] = []
        if target.destinations.contains(.iPhone) { deviceFamilyValues.append(1) }
        if target.destinations.contains(.iPad) { deviceFamilyValues.append(2) }
        if target.destinations.contains(.appleTv) { deviceFamilyValues.append(3) }
        if target.destinations.contains(.appleWatch) { deviceFamilyValues.append(4) }
        if target.destinations.contains(.appleVision) { deviceFamilyValues.append(7) }

        if !deviceFamilyValues.isEmpty {
            settings["TARGETED_DEVICE_FAMILY"] = .string(deviceFamilyValues.map { "\($0)" }.joined(separator: ","))
        }

        if target.supportedPlatforms.contains(.iOS) {
            if target.destinations.contains(.macWithiPadDesign) {
                settings["SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD"] = "YES"
            } else {
                settings["SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD"] = "NO"
            }

            if target.destinations.contains(.appleVisionWithiPadDesign) {
                settings["SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD"] = "YES"
            } else {
                settings["SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD"] = "NO"
            }

            if target.destinations.contains(.macCatalyst) {
                settings["SUPPORTS_MACCATALYST"] = "YES"
                settings["DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER"] = "YES"
            } else {
                settings["SUPPORTS_MACCATALYST"] = "NO"
            }
        }

        return settings
    }

    private func deploymentTargetDerivedSettings(target: Target) -> SettingsDictionary {
        var settings: SettingsDictionary = [:]

        if let iOSVersion = target.deploymentTargets.iOS {
            settings["IPHONEOS_DEPLOYMENT_TARGET"] = .string(iOSVersion)
        }

        if let macOSVersion = target.deploymentTargets.macOS {
            settings["MACOSX_DEPLOYMENT_TARGET"] = .string(macOSVersion)
        }

        if let watchOSVersion = target.deploymentTargets.watchOS {
            settings["WATCHOS_DEPLOYMENT_TARGET"] = .string(watchOSVersion)
        }

        if let tvOSVersion = target.deploymentTargets.tvOS {
            settings["TVOS_DEPLOYMENT_TARGET"] = .string(tvOSVersion)
        }

        if let visionOSVersion = target.deploymentTargets.visionOS {
            settings["XROS_DEPLOYMENT_TARGET"] = .string(visionOSVersion)
        }

        return settings
    }

    private func watchTargetDerivedSettings(
        target: Target,
        graphTraverser: GraphTraversing,
        projectPath: AbsolutePath
    ) -> SettingsDictionary {
        guard target.product == .watch2App else {
            return [:]
        }

        let targetDependencies = graphTraverser.directLocalTargetDependencies(path: projectPath, name: target.name).sorted()
        guard let watchExtension = targetDependencies.first(where: { $0.target.product == .watch2Extension }) else {
            return [:]
        }

        return [
            "IBSC_MODULE": .string(watchExtension.target.productName),
        ]
    }
}
