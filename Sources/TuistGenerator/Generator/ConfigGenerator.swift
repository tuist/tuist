import Foundation
import Path
import TuistCore
import TuistSupport
import XcodeGraph
import XcodeProj

protocol ConfigGenerating: AnyObject {
    func generateProjectConfig(
        project: Project,
        pbxproj: PBXProj,
        fileElements: ProjectFileElements
    ) async throws -> XCConfigurationList

    func generateTargetConfig(
        _ target: Target,
        project: Project,
        pbxTarget: PBXTarget,
        pbxproj: PBXProj,
        projectSettings: Settings,
        fileElements: ProjectFileElements,
        graphTraverser: GraphTraversing,
        sourceRootPath: AbsolutePath
    ) async throws
}

// swiftlint:disable:next type_body_length
final class ConfigGenerator: ConfigGenerating {
    // MARK: - Attributes

    private let defaultSettingsProvider: DefaultSettingsProviding

    // MARK: - Init

    init(
        defaultSettingsProvider: DefaultSettingsProviding = DefaultSettingsProvider()
    ) {
        self.defaultSettingsProvider = defaultSettingsProvider
    }

    // MARK: - ConfigGenerating

    func generateProjectConfig(
        project: Project,
        pbxproj: PBXProj,
        fileElements: ProjectFileElements
    ) async throws -> XCConfigurationList {
        /// Configuration list
        let defaultConfiguration = project.settings.defaultReleaseBuildConfiguration()
            ?? project.settings.defaultDebugBuildConfiguration()
        let configurationList = XCConfigurationList(
            buildConfigurations: [],
            defaultConfigurationName: project.settings.defaultConfiguration ?? defaultConfiguration?.name
        )
        pbxproj.add(object: configurationList)

        for item in project.settings.configurations.sortedByBuildConfigurationName() {
            try await generateProjectSettingsFor(
                buildConfiguration: item.key,
                configuration: item.value,
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
    ) async throws {
        let defaultConfiguration = projectSettings.defaultReleaseBuildConfiguration()
            ?? projectSettings.defaultDebugBuildConfiguration()
        let configurationList = XCConfigurationList(
            buildConfigurations: [],
            defaultConfigurationName: projectSettings.defaultConfiguration ?? defaultConfiguration?.name
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
        for orderedConfiguration in orderedConfigurations {
            try await generateTargetSettingsFor(
                target: target,
                project: project,
                buildConfiguration: orderedConfiguration.key,
                configuration: orderedConfiguration.value,
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
    ) async throws {
        let settingsHelper = SettingsHelper()
        var settings = try await defaultSettingsProvider.projectSettings(
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
        variantBuildConfiguration.buildSettings = settings.toBuildSettings()
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
    ) async throws {
        let settingsHelper = SettingsHelper()

        var settings: SettingsDictionary = try await defaultSettingsProvider.targetSettings(
            target: target,
            project: project,
            buildConfiguration: buildConfiguration,
            graphTraverser: graphTraverser
        )

        updateTargetDerived(
            buildSettings: &settings,
            target: target,
            graphTraverser: graphTraverser,
            project: project,
            sourceRootPath: sourceRootPath
        )

        settingsHelper.extend(buildSettings: &settings, with: target.settings?.base ?? [:])
        if buildConfiguration.variant == .debug {
            settingsHelper.extend(buildSettings: &settings, with: target.settings?.baseDebug ?? [:])
        }
        settingsHelper.extend(buildSettings: &settings, with: configuration?.settings ?? [:])
        settingsHelper
            .extend(
                buildSettings: &settings,
                with: swiftMacrosDerivedSettings(
                    target: target,
                    graphTraverser: graphTraverser,
                    projectPath: project.path
                ),
                inherit: true
            )

        let variantBuildConfiguration = XCBuildConfiguration(
            name: buildConfiguration.xcodeValue,
            baseConfiguration: nil,
            buildSettings: [:]
        )
        if let variantConfig = configuration, let xcconfig = variantConfig.xcconfig {
            let fileReference = fileElements.file(path: xcconfig)
            variantBuildConfiguration.baseConfiguration = fileReference
        }

        variantBuildConfiguration.buildSettings = settings.toBuildSettings()
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
        settings.merge(destinationsDerivedSettings(target: target)) { $1 }
        settings.merge(deploymentTargetDerivedSettings(target: target)) { $1 }
        settings
            .merge(watchTargetDerivedSettings(target: target, graphTraverser: graphTraverser, projectPath: project.path)) { $1 }
    }

    private func generalTargetDerivedSettings(
        target: Target,
        sourceRootPath: AbsolutePath,
        project: Project
    ) -> SettingsDictionary {
        var settings: SettingsDictionary = [:]
        settings["PRODUCT_BUNDLE_IDENTIFIER"] = .string(target.bundleId)

        // Info.plist
        if let infoPlist = target.infoPlist {
            if let path = infoPlist.path {
                let relativePath = path.relative(to: sourceRootPath).pathString
                if project.xcodeProjPath.parentDirectory == sourceRootPath {
                    settings["INFOPLIST_FILE"] = .string(relativePath)
                } else {
                    settings["INFOPLIST_FILE"] = .string("$(SRCROOT)/\(relativePath)")
                }
            } else if case let .variable(configName, configuration: _) = infoPlist {
                settings["INFOPLIST_FILE"] = .string(configName)
            }
        }

        // Entitlements
        if let entitlements = target.entitlements {
            if let path = entitlements.path {
                let relativePath = path.relative(to: sourceRootPath).pathString
                if project.xcodeProjPath.parentDirectory == sourceRootPath {
                    settings["CODE_SIGN_ENTITLEMENTS"] = .string(relativePath)
                } else {
                    settings["CODE_SIGN_ENTITLEMENTS"] = .string("$(SRCROOT)/\(relativePath)")
                }
            } else if case let .variable(configName, configuration: _) = entitlements {
                settings["CODE_SIGN_ENTITLEMENTS"] = .string(configName)
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

        if target.mergeable {
            settings["MERGEABLE_LIBRARY"] = .string("YES")
        }

        switch target.mergedBinaryType {
        case .disabled:
            // When `MERGED_BINARY_TYPE` is disabled, `MERGED_BINARY_TYPE` value should be left empty
            break
        case .automatic:
            settings["MERGED_BINARY_TYPE"] = .string("automatic")
        case .manual:
            settings["MERGED_BINARY_TYPE"] = .string("manual")
        }

        return settings
    }

    private func swiftMacrosDerivedSettings(
        target: Target,
        graphTraverser: GraphTraversing,
        projectPath: AbsolutePath
    ) -> SettingsDictionary {
        let pluginExecutables = graphTraverser.allSwiftPluginExecutables(path: projectPath, name: target.name)
        var settings: SettingsDictionary = [:]
        if pluginExecutables.isEmpty { return settings }
        let swiftCompilerFlags = pluginExecutables.sorted().flatMap { ["-load-plugin-executable", $0] }
        settings["OTHER_SWIFT_FLAGS"] = .array(swiftCompilerFlags)
        return settings
    }

    private func destinationsDerivedSettings(target: Target) -> SettingsDictionary {
        var settings: SettingsDictionary = [:]

        var deviceFamilyValues: [Int] = []
        if target.destinations.contains(.iPhone) { deviceFamilyValues.append(1) }
        if target.destinations.contains(.iPad) { deviceFamilyValues.append(2) }
        if target.destinations.contains(.appleTv) { deviceFamilyValues.append(3) }
        if target.destinations.contains(.appleWatch) { deviceFamilyValues.append(4) }
        if target.destinations.contains(.macCatalyst) { deviceFamilyValues.append(6) }
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

        if let initialInstallTags = target.onDemandResourcesTags?.initialInstall, !initialInstallTags.isEmpty {
            settings["ON_DEMAND_RESOURCES_INITIAL_INSTALL_TAGS"] = .string(
                initialInstallTags.sorted().map {
                    $0.replacingOccurrences(of: " ", with: "\\ ")
                }.joined(separator: " ")
            )
        }

        if let prefetchOrder = target.onDemandResourcesTags?.prefetchOrder, !prefetchOrder.isEmpty {
            settings["ON_DEMAND_RESOURCES_PREFETCH_ORDER"] = .string(
                prefetchOrder.map {
                    $0.replacingOccurrences(of: " ", with: "\\ ")
                }.joined(separator: " ")
            )
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
